defmodule Palee.Application.LeaderboardProfile do
  @moduledoc """
  ADR-356 (CP-D2): what a person tells a box's leaderboards so they are
  compared fairly: their division (`women`, `men` or none) and birth year.
  Both live on the person's opt-in row of this box, so only someone who
  opted in can set them, and opting out deletes them.
  """

  alias Palee.Gamification

  @doc "`%{opted_in, division, birth_year}` of the signed-in person at this box."
  def get(%{organization_id: organization_id, user_id: user_id} = context)
      when is_binary(organization_id) do
    Gamification.with_tenant_context(context, fn ->
      case Gamification.leaderboard_profiles([user_id]) do
        %{^user_id => profile} -> {:ok, Map.put(profile, :opted_in, true)}
        _none -> {:ok, %{opted_in: false, division: nil, birth_year: nil}}
      end
    end)
  end

  def get(_context), do: {:error, :organization_context_required}

  @doc "Sets `division` and `birth_year` (nil clears either)."
  def put(%{organization_id: organization_id, user_id: user_id} = context, params)
      when is_binary(organization_id) and is_map(params) do
    changes = Map.take(normalize(params), [:division, :birth_year])

    Gamification.with_tenant_context(context, fn ->
      case Gamification.put_leaderboard_profile(user_id, changes) do
        {:ok, profile} -> {:ok, Map.put(profile, :opted_in, true)}
        {:error, :not_opted_in} -> {:error, :leaderboard_not_opted_in}
        error -> error
      end
    end)
  end

  def put(_context, _params), do: {:error, :organization_context_required}

  defp normalize(params) do
    Enum.reduce([:division, :birth_year], %{}, fn key, acc ->
      case Map.fetch(params, key) do
        {:ok, value} ->
          Map.put(acc, key, value)

        :error ->
          case Map.fetch(params, Atom.to_string(key)) do
            {:ok, value} -> Map.put(acc, key, value)
            :error -> acc
          end
      end
    end)
  end
end
