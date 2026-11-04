defmodule Palee.Application.SetTrainsWithPalee do
  @moduledoc """
  ADR-463: a staff member says whether they also train with Palee, once in
  the first run and later in Εγώ › Ρυθμίσεις. `false` hides the prompts aimed
  at athletes in the member app; `nil` (never asked) reads as `true`.
  """

  alias Palee.Identity

  def call(%{id: user_id}, trains?) when is_boolean(trains?) do
    with {:ok, account} <- Identity.update_trains_with_palee(user_id, trains?),
         do: {:ok, account.trains_with_palee}
  end

  def call(_user, _trains?), do: {:error, :invalid_trains_with_palee}
end
