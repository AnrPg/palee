defmodule Palee.Application.GetFitnessProfile do
  @moduledoc """
  ADR-358 (CP-D6): «Επίπεδο φυσικής κατάστασης» in the Journal: a score per
  domain (strength, power, gymnastics, monostructural, metcon) from the
  person's own PRs, the reasoning behind each number, and up to three
  suggestions of what to work on (`Pantheon.Domain.FitnessProfile`).

  Account-level and the person's own data only, like Πρόοδος (ADR-165):
  PRs from every box, training qualities of the last 12 weeks and whether
  an injury is active. Never compared with other people (principle §4.4).
  `division` (`women`, `men`) picks the standards; without it the neutral
  mean is used and the response says so.

  ADR-395 (version 2): the person's own settings (body weight, birth year,
  what the card shows) and their coaches' choices shape the answer.
  `period` (Πρόοδος's period bar: `4w`, `12w`, `6m`, `1y`) adds how each
  domain moved since the start of the period, from the PR history; `all`
  or none adds no change. `display` says what the card shows and who set
  it; with `progress_only` or `none` the scores never leave the server.
  """

  alias Palee.{Pantheon, Wellbeing}
  alias Palee.Analytics.Domain.ProgressFilter
  alias Palee.Application.TrainingDepth
  alias Palee.Pantheon.Domain.{FitnessBenchmarks, FitnessProfile}
  alias Palee.Pantheon.FitnessSettingsStore

  @divisions ~w(women men)
  # The same periods as Πρόοδος's filter, so the change covers the page's period.
  @periods ~w(4w 12w 6m 1y)

  def call(context, params, today \\ Date.utc_today())

  def call(%{user_id: user_id} = context, params, today) when is_binary(user_id) do
    with {:ok, division} <- division(param(params, :division)),
         {:ok, since} <- since(param(params, :period), today) do
      {prs, history, settings, overrides} =
        Pantheon.with_user_context(context, fn ->
          {
            list(Pantheon.list_records(user_id)),
            if(since, do: list(Pantheon.list_user_record_history(user_id)), else: []),
            FitnessSettingsStore.get_settings(user_id),
            Enum.map(FitnessSettingsStore.list_overrides_for_client(user_id), & &1.display)
          }
        end)
        |> scoped()

      depth = TrainingDepth.build(context, "12w", today)
      settings = settings || %{body_weight_kg: nil, birth_year: nil, display: "all"}

      input = %{
        prs: prs,
        today: today,
        division: division,
        qualities: %{sessions: depth.coverage.sessions, qualities: depth.qualities.qualities},
        active_injury: active_injury?(context, user_id),
        body_weight_kg: settings.body_weight_kg,
        age: age(settings.birth_year, today)
      }

      profile = Pantheon.fitness_profile(input)

      profile =
        case since do
          nil ->
            profile

          %Date{} = from ->
            # The profile as it stood on the period's first day: the PRs of
            # then, aged from then (a PR that went stale later still counts
            # in full) and the age band the person was in then.
            previous =
              Pantheon.fitness_profile(%{
                input
                | prs: FitnessProfile.as_of(prs, history, from),
                  today: from,
                  age: age(settings.birth_year, from)
              })

            FitnessProfile.with_change(profile, previous)
        end

      display = FitnessProfile.display(settings.display, overrides)

      {:ok,
       profile
       |> FitnessProfile.for_display(display.mode)
       |> Map.merge(%{display: display, settings: settings, period_from: since})}
    end
  end

  def call(_context, _params, _today), do: {:error, :unauthorized}

  # The age counts only once the reviewing coach set the age bands' numbers.
  defp age(year, today) when is_integer(year) do
    if FitnessBenchmarks.age_ready?(), do: today.year - year
  end

  defp age(_year, _today), do: nil

  defp scoped({_prs, _history, _settings, _overrides} = result), do: result
  defp scoped(_unreadable), do: {[], [], nil, []}

  defp list(rows) when is_list(rows), do: rows
  defp list(_rows), do: []

  defp active_injury?(context, user_id) do
    case Wellbeing.with_tenant_context(context, fn ->
           Wellbeing.list_active_injuries_for_user(user_id)
         end) do
      [_ | _] -> true
      _none -> false
    end
  end

  defp division(nil), do: {:ok, nil}
  defp division(""), do: {:ok, nil}
  defp division(value) when value in @divisions, do: {:ok, value}
  defp division(_value), do: {:error, {:invalid_leaderboard_filter, :division}}

  defp since(nil, _today), do: {:ok, nil}
  defp since("", _today), do: {:ok, nil}
  defp since("all", _today), do: {:ok, nil}

  defp since(period, today) when period in @periods,
    do: {:ok, ProgressFilter.since(%ProgressFilter{range: period}, today)}

  defp since(_period, _today), do: {:error, {:invalid_leaderboard_filter, :period}}

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
