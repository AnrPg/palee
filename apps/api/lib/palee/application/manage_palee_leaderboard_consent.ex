defmodule Palee.Application.ManagePaleeLeaderboardConsent do
  @moduledoc """
  ADR-394: the person's own answer to «Να μπει το σκορ σου στον πίνακα όλου
  του Palee;», asked once on the first tap of «Όλο το Palee» and kept as a
  switch in «Κοινοποίηση και ορατότητα».

    * `share` – others see their nickname, box and score;
    * `see_only` – they see the board and their own place, nobody sees them;
    * withdrawn – the row is deleted, so they leave every Palee-wide board
      at once (the boards are computed on read).

  Separate from each box's leaderboard opt-in (principle §4.4).
  """

  alias Palee.Gamification

  def get(%{user_id: user_id} = context) do
    Gamification.with_tenant_context(context, fn ->
      {:ok, %{choice: Gamification.palee_leaderboard_consent(user_id)}}
    end)
  end

  def put(%{user_id: user_id} = context, choice) do
    if choice in Gamification.palee_leaderboard_choices() do
      Gamification.with_tenant_context(context, fn ->
        with {:ok, saved} <- Gamification.put_palee_leaderboard_consent(user_id, choice),
             do: {:ok, %{choice: saved}}
      end)
    else
      {:error, :invalid_palee_leaderboard_choice}
    end
  end

  def withdraw(%{user_id: user_id} = context) do
    Gamification.with_tenant_context(context, fn ->
      :ok = Gamification.withdraw_palee_leaderboard_consent(user_id)
      {:ok, %{choice: nil}}
    end)
  end
end
