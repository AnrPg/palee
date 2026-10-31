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
  """

  alias Palee.{Pantheon, Wellbeing}
  alias Palee.Application.TrainingDepth

  @divisions ~w(women men)

  def call(context, params, today \\ Date.utc_today())

  def call(%{user_id: user_id} = context, params, today) when is_binary(user_id) do
    with {:ok, division} <- division(param(params, :division)) do
      prs =
        case Pantheon.with_user_context(context, fn -> Pantheon.list_records(user_id) end) do
          records when is_list(records) -> records
          _unreadable -> []
        end

      depth = TrainingDepth.build(context, "12w", today)

      {:ok,
       Pantheon.fitness_profile(%{
         prs: prs,
         today: today,
         division: division,
         qualities: %{sessions: depth.coverage.sessions, qualities: depth.qualities.qualities},
         active_injury: active_injury?(context, user_id)
       })}
    end
  end

  def call(_context, _params, _today), do: {:error, :unauthorized}

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

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
