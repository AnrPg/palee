defmodule Palee.Application.ManageFitnessSettings do
  @moduledoc """
  ADR-395: the person's own settings for «Επίπεδο φυσικής κατάστασης», in
  the card's «Προχωρημένα»:

    * `body_weight_kg` – the lifts read as a multiple of it (nil: in kg);
    * `birth_year` – the age band (counts once the coach set the bands);
    * `display` – `all`, `progress_only` (only the direction of change and
      «Τι να δουλέψεις») or `none`.

  Account level and private: the person and the coach who coaches them
  (`ClientFitnessDisplay`) read it, nobody else.
  """

  alias Palee.Pantheon
  alias Palee.Pantheon.FitnessSettingsStore

  @fields ~w(body_weight_kg birth_year display)

  def get(%{user_id: user_id} = context) when is_binary(user_id) do
    Pantheon.with_user_context(context, fn ->
      {:ok, FitnessSettingsStore.get_settings(user_id) || empty()}
    end)
  end

  def get(_context), do: {:error, :unauthorized}

  def put(%{user_id: user_id} = context, params) when is_binary(user_id) and is_map(params) do
    changes =
      for field <- @fields,
          Map.has_key?(params, field) or Map.has_key?(params, String.to_atom(field)),
          into: %{},
          do:
            {String.to_atom(field),
             Map.get(params, field, Map.get(params, String.to_atom(field)))}

    Pantheon.with_user_context(context, fn ->
      FitnessSettingsStore.put_settings(user_id, changes)
    end)
  end

  def put(_context, _params), do: {:error, :unauthorized}

  defp empty, do: %{body_weight_kg: nil, birth_year: nil, display: "all"}
end
