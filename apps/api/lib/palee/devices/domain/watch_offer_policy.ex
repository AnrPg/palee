defmodule Palee.Devices.Domain.WatchOfferPolicy do
  @moduledoc """
  When the phone puts the timer on the watch (ANR's D8 rules, 2026-11-01;
  ADR-375 amendment 2026-11-03). Pure: the caller gathers the facts.

    * Only when a WOD is **opened for execution**: the phone asks while the
      execution is open, never through a notification or on a schedule.
    * Only when the watch is **detected and connected at that moment** (the
      phone says so; the server cannot see the watch).
    * A box class WOD only when the person is **checked in to that class**.
    * **Box members** are asked on their first five qualifying WODs; after
      that the watch starts on its own under the same conditions.
    * **Free athletes** (no box) are asked every time.

  An execution is decided once: opening it again gives the same outcome
  (`existing`), so a reopened WOD neither asks twice nor counts twice.
  """

  @ask_limit 5

  @type facts :: %{
          required(:execution_open?) => boolean(),
          required(:watch_connected?) => boolean(),
          required(:class_wod?) => boolean(),
          required(:checked_in?) => boolean(),
          required(:box_member?) => boolean(),
          required(:asked_before) => non_neg_integer(),
          optional(:existing) => %{mode: String.t(), answer: String.t() | nil} | nil
        }

  @type outcome ::
          {:ask, atom()} | {:start, atom()} | {:none, atom()}

  def ask_limit, do: @ask_limit

  @doc """
  `{:ask, reason}` – show «Το χρονόμετρο και στο ρολόι;»;
  `{:start, reason}` – put the timer on the watch without asking;
  `{:none, reason}` – leave the watch alone.
  """
  @spec decide(facts()) :: outcome()
  def decide(facts) do
    cond do
      not facts.execution_open? -> {:none, :execution_closed}
      not facts.watch_connected? -> {:none, :watch_not_connected}
      facts.class_wod? and not facts.checked_in? -> {:none, :not_checked_in}
      existing = Map.get(facts, :existing) -> repeat(existing)
      not facts.box_member? -> {:ask, :free_athlete}
      facts.asked_before < @ask_limit -> {:ask, :first_wods}
      true -> {:start, :box_member_after_first_wods}
    end
  end

  @doc "The row to store for a new `:ask` or `:start` outcome; nil otherwise."
  def mode({:ask, _reason}), do: "asked"
  def mode({:start, _reason}), do: "auto"
  def mode(_outcome), do: nil

  @doc "Whether an answer may be recorded on this offer."
  def answerable?(%{mode: "asked"}), do: true
  def answerable?(_offer), do: false

  defp repeat(%{mode: "auto"}), do: {:start, :already_started}
  defp repeat(%{mode: "asked", answer: "yes"}), do: {:start, :answered_yes}
  defp repeat(%{mode: "asked", answer: "no"}), do: {:none, :answered_no}
  defp repeat(%{mode: "asked"}), do: {:ask, :not_answered}
end
