defmodule Palee.Application.Retention.MembersAtRisk do
  @moduledoc """
  ADR-347: «Σε κίνδυνο» (`PaleeWeb.AdminMemberRiskController` and the daily
  job). Once a day each box's active clients get their score again from
  their own attendance, bookings, subscription packages and invoices at
  this box. Staff see who is at medium or high risk, why, and what to do;
  «Μίλησα» records a contact, «Το είδα» hides someone until a date.

  A member whose level becomes `high` is announced once per high spell
  (`:member_at_risk`), which queues the win-back recipe (ADR-346) when the
  box has it on.
  """

  alias Palee.{DomainEvents, Identity, Organizations, Retention}
  alias Palee.Retention.Risk

  @contact_channels ~w(phone email message in_person)
  @max_snooze_days 90

  def contact_channels, do: @contact_channels

  @doc "Scores every active client of the box. Answers `%{scored, high, newly_high}`."
  def refresh(%{organization_id: organization_id} = context, now \\ Retention.now()) do
    today = Organizations.local_today(organization_id, now)
    signals = Retention.signals(context, today, now)
    previous = Retention.all(context)

    results =
      Enum.map(signals, fn {user_id, member_signals} ->
        result = Retention.score(member_signals)
        before = Map.get(previous, user_id)
        level_since = level_since(before, result.level, now)
        newly_high? = result.level == "high" and not high_spell_announced?(before, level_since)

        {:ok, _risk} =
          Retention.put(context, user_id, %{
            score: result.score,
            level: result.level,
            reasons: Enum.map(result.reasons, &stringify/1),
            suggested_action: result.suggested_action,
            computed_at: now,
            level_since: level_since,
            win_back_queued_at:
              if(newly_high?, do: now, else: before && before.win_back_queued_at)
          })

        if newly_high? do
          DomainEvents.publish(:member_at_risk, %{
            organization_id: organization_id,
            user_id: user_id,
            score: result.score,
            level_since: level_since,
            at: now
          })
        end

        {result.level, newly_high?}
      end)

    Retention.delete_except(context, Map.keys(signals))

    %{
      scored: length(results),
      high: Enum.count(results, fn {level, _new} -> level == "high" end),
      newly_high: Enum.count(results, fn {_level, new?} -> new? end)
    }
  end

  defp level_since(%Risk{level: level, level_since: since}, level, _now), do: since
  defp level_since(_before, _level, now), do: now

  # One win-back per spell at high: announced when it started, not again.
  defp high_spell_announced?(%Risk{level: "high", win_back_queued_at: %DateTime{} = queued}, since),
    do: DateTime.compare(queued, since) != :lt

  defp high_spell_announced?(_before, _since), do: false

  @doc """
  The list: members at `level` (`high`, `medium`, or `all` for both),
  highest score first, with the person, the reasons and the suggested
  action. Snoozed members are left out unless `include_snoozed=true`.
  """
  def list(%{organization_id: organization_id} = context, params) do
    today = Organizations.local_today(organization_id, Retention.now())

    levels =
      case params["level"] do
        "high" -> ["high"]
        "medium" -> ["medium"]
        _all -> ["high", "medium"]
      end

    risks =
      Retention.list(context, %{
        levels: levels,
        today: today,
        include_snoozed: params["include_snoozed"] in [true, "true"],
        limit: limit(params["limit"])
      })

    people = people(Enum.flat_map(risks, &[&1.user_id, &1.contacted_by_id]))
    counts = Retention.level_counts(context)

    %{
      members: Enum.map(risks, &present(&1, people)),
      counts: Map.new(Retention.levels(), &{&1, Map.get(counts, &1, 0)}),
      computed_at: risks |> Enum.map(& &1.computed_at) |> Enum.max(DateTime, fn -> nil end)
    }
  end

  @doc "One member's risk with its reasons."
  def show(context, user_id) do
    case Retention.get(context, user_id) do
      nil -> {:error, :not_found}
      risk -> {:ok, present(risk, people([risk.user_id, risk.contacted_by_id]))}
    end
  end

  @doc "«Μίλησα»: staff reached the member (`channel`)."
  def contacted(context, user_id, params) do
    channel = params["channel"] || "phone"

    with true <- channel in @contact_channels || {:error, {:invalid_fields, %{"channel" => "invalid"}}},
         %Risk{} <- Retention.get(context, user_id) || {:error, :not_found},
         {:ok, risk} <-
           Retention.put(context, user_id, %{
             contacted_at: Retention.now(),
             contacted_by_id: Map.get(context, :user_id)
           }) do
      {:ok, present(risk, people([risk.user_id, risk.contacted_by_id]))}
    end
  end

  @doc "«Το είδα»: hides the member from the list for `days` (1 to 90), or shows them again (0)."
  def snooze(%{organization_id: organization_id} = context, user_id, params) do
    days = params["days"]

    with true <-
           (is_integer(days) and days in 0..@max_snooze_days) ||
             {:error, {:invalid_fields, %{"days" => "invalid"}}},
         %Risk{} <- Retention.get(context, user_id) || {:error, :not_found},
         until =
           if(days == 0,
             do: nil,
             else: Date.add(Organizations.local_today(organization_id, Retention.now()), days)
           ),
         {:ok, risk} <- Retention.put(context, user_id, %{snoozed_until: until}) do
      {:ok, present(risk, people([risk.user_id, risk.contacted_by_id]))}
    end
  end

  defp present(%Risk{} = risk, people) do
    %{
      user_id: risk.user_id,
      person: Map.get(people, risk.user_id),
      score: risk.score,
      level: risk.level,
      reasons: risk.reasons,
      suggested_action: risk.suggested_action,
      computed_at: risk.computed_at,
      level_since: risk.level_since,
      snoozed_until: risk.snoozed_until,
      contacted_at: risk.contacted_at,
      contacted_by: Map.get(people, risk.contacted_by_id),
      win_back_queued_at: risk.win_back_queued_at
    }
  end

  defp people(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] ->
        %{}

      ids ->
        ids
        |> Identity.list_by_ids()
        |> Map.new(
          &{&1.id,
           %{
             user_id: &1.id,
             display_name: &1.nickname,
             handle: &1.handle,
             avatar_url: &1.avatar_url
           }}
        )
    end
  end

  defp stringify(%{code: code, points: points, facts: facts}),
    do: %{"code" => code, "points" => points, "facts" => facts}

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _other -> 100
    end
  end

  defp limit(_value), do: 100
end
