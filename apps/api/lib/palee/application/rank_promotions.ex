defmodule Palee.Application.RankPromotions do
  @moduledoc """
  A coach promotes a client (ADR-377): the client's standing on each
  ladder, a new rank or stripe with the skills ticked, a withdrawal with a
  reason, and the diploma. Coaches reach their own clients, staff with
  full coaching scope everyone (`manage_coaching`, ADR-100).
  """

  alias Palee.Application.{
    AuthorizeClientAccess,
    Clock,
    DiplomaSignatures,
    RankCertificates,
    RankStanding
  }

  alias Palee.Ranks

  def client(context, user_id) do
    with :ok <- AuthorizeClientAccess.call(context, :manage_coaching, user_id) do
      {:ok, %{user_id: user_id, ladders: RankStanding.call(context, user_id)}}
    end
  end

  def award(%{organization_id: organization_id} = context, staff_id, user_id, params) do
    with :ok <- AuthorizeClientAccess.call(context, :manage_coaching, user_id) do
      today = Clock.today()
      # The diploma keeps the coach's signature of today (ADR-377 addendum).
      signature_id = DiplomaSignatures.current_id(staff_id)

      Ranks.with_context(context, fn ->
        with {:ok, ladder} <- fetch_ladder(get(params, "ladder_id")),
             {:ok, rank} <- fetch_rank(ladder, get(params, "rank_id")),
             {:ok, stripes, skills, on} <- award_fields(params, today),
             awards = user_id |> Ranks.list_awards() |> Enum.filter(&(&1.ladder_id == ladder.id)),
             current = Ranks.current_award(awards),
             current_rank = current && Enum.find(ladder.ranks, &(&1.id == current.rank_id)),
             :ok <-
               Ranks.validate_award(
                 rank,
                 stripes,
                 skills,
                 current_rank,
                 (current && current.stripes) || 0,
                 on,
                 today
               ),
             id = Ecto.UUID.generate(),
             {:ok, award} <-
               Ranks.insert_award(%{
                 id: id,
                 organization_id: organization_id,
                 ladder_id: ladder.id,
                 rank_id: rank.id,
                 user_id: user_id,
                 stripes: stripes,
                 awarded_on: on,
                 awarded_by_id: staff_id,
                 note: get(params, "note"),
                 skills_checked: skills,
                 certificate_number: Ranks.certificate_number(id, on),
                 signature_id: signature_id
               }) do
          {:ok, RankStanding.present_award(award, Map.new(ladder.ranks, &{&1.id, &1}))}
        end
      end)
    end
  end

  def revoke(context, staff_id, award_id, params) do
    Ranks.with_context(context, fn ->
      with %{} = award <- Ranks.get_award(award_id) || {:error, :not_found},
           :ok <- AuthorizeClientAccess.call(context, :manage_coaching, award.user_id),
           :ok <- if(award.revoked_at, do: {:error, :award_already_revoked}, else: :ok),
           {:ok, award} <-
             Ranks.revoke_award(award, %{
               revoked_at: Clock.now(),
               revoked_by_id: staff_id,
               revoke_reason: get(params, "reason")
             }) do
        {:ok, RankStanding.present_award(award, %{})}
      end
    end)
  end

  def certificate(context, award_id) do
    award = Ranks.with_context(context, fn -> Ranks.get_award(award_id) end)

    with %{} <- award || {:error, :not_found},
         :ok <- AuthorizeClientAccess.call(context, :manage_coaching, award.user_id) do
      RankCertificates.call(context, award_id)
    end
  end

  defp fetch_ladder(id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = ladder <- Ranks.get_ladder(id) do
      {:ok, ladder}
    else
      _missing -> {:error, :unknown_rank}
    end
  end

  defp fetch_ladder(_id), do: {:error, :unknown_rank}

  defp fetch_rank(ladder, id) do
    case Enum.find(ladder.ranks, &(&1.id == id)) do
      nil -> {:error, :unknown_rank}
      rank -> {:ok, rank}
    end
  end

  defp award_fields(params, today) do
    stripes = get(params, "stripes") || 0
    skills = get(params, "skills_checked") || []

    on =
      case get(params, "awarded_on") do
        nil -> {:ok, today}
        %Date{} = date -> {:ok, date}
        text when is_binary(text) -> Date.from_iso8601(text)
        _other -> :error
      end

    case on do
      {:ok, date} when is_integer(stripes) and is_list(skills) -> {:ok, stripes, skills, date}
      _invalid -> {:error, :invalid_rank_award}
    end
  end

  defp params_map(params) when is_struct(params), do: params |> Map.from_struct() |> params_map()

  defp params_map(params) when is_map(params),
    do: Map.new(params, fn {k, v} -> {to_string(k), v} end)

  defp get(params, key), do: Map.get(params_map(params), key)
end
