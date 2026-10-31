defmodule Palee.Automations.Ports.AutomationStore do
  @moduledoc """
  ADR-346: the box's recipe choices, the outbox of automatic messages and
  box members' preferences. Every call runs in the box's `RepoContext`.

  The outbox is claimed with one statement (`FOR UPDATE SKIP LOCKED`), so
  two workers never send the same message; a `sending` row whose worker
  died is claimed again after `claim_timeout_seconds`.
  """

  alias Palee.Automations.{BoxAutomation, Delivery, MemberPreference}

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback list_automations(context()) :: [BoxAutomation.t()]
  @callback get_automation(context(), String.t()) :: BoxAutomation.t() | nil
  @callback put_automation(context(), String.t(), map()) ::
              {:ok, BoxAutomation.t()} | {:error, Ecto.Changeset.t()}

  @doc "Queues a delivery; an existing one with the same recipe and `trigger_ref` is kept (`:existing`)."
  @callback enqueue(context(), map()) ::
              {:ok, Delivery.t(), :created | :existing} | {:error, Ecto.Changeset.t()}

  @doc "Claims up to `limit` due deliveries (`pending` and due, or stale `sending`) as `sending`."
  @callback claim_due(context(), DateTime.t(), pos_integer(), pos_integer()) :: [Delivery.t()]

  @callback finish(context(), id(), map()) :: {:ok, Delivery.t()} | {:error, term()}

  @doc "Deliveries, newest first. Filters: `recipe`, `user_id`, `lead_id`, `status`, `limit`."
  @callback list_deliveries(context(), map()) :: [Delivery.t()]

  @doc "Counts per recipe and status for deliveries created since the moment."
  @callback delivery_stats(context(), DateTime.t()) :: %{
              String.t() => %{String.t() => non_neg_integer()}
            }

  @doc "Cancels pending deliveries of a recipe (switched off) or of a person (opted out)."
  @callback cancel_pending(context(), map()) :: non_neg_integer()

  @callback get_preference(context(), id()) :: MemberPreference.t() | nil
  @callback put_preference(context(), id(), map()) ::
              {:ok, MemberPreference.t()} | {:error, Ecto.Changeset.t()}

  @doc "Profiles that shared this birthday with the box and did not opt out."
  @callback birthdays(context(), 1..12, 1..31) :: [id()]
end
