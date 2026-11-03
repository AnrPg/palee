defmodule Palee.Application.Programmes.Sweep do
  @moduledoc """
  ADR-371: the hourly programme sweep over every active business.

    * An `active` purchase past its last day (`ends_on`, on the business's
      own clock) becomes `completed`; its WODs stay in the buyer's history.
    * A `pending_payment` purchase older than a day whose checkout never
      opened, or whose payment failed, was cancelled or expired, becomes
      `cancelled`. A payment still open (or already succeeded and waiting
      for its fulfilment) is left alone, so a late success is never lost.

  Every step is a lifecycle transition under the row lock, so a run that
  overlaps another, or a retry, changes nothing twice.
  """

  require Logger

  alias Palee.{Organizations, Payments, Programmes}

  @stale_after_seconds 24 * 3_600
  @closed_payments ~w(failed cancelled expired)

  def call(now \\ DateTime.utc_now()) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      try do
        sweep(%{organization_id: organization.id}, now)
      rescue
        error ->
          Logger.error(
            "programme_sweep_failed organization_id=#{organization.id} #{Exception.message(error)}"
          )
      end
    end)
  end

  @doc "One business: `%{completed: n, cancelled: n}`."
  def sweep(%{organization_id: organization_id} = context, %DateTime{} = now) do
    today = Organizations.local_today(organization_id, now)

    completed =
      context
      |> Programmes.due_completions(today)
      |> Enum.count(&match?({:ok, _}, Programmes.step_purchase(context, &1.id, :complete, now)))

    cancelled =
      context
      |> Programmes.list_purchases(%{statuses: ["pending_payment"], limit: 500})
      |> Enum.filter(&stale?(context, &1, now))
      |> Enum.count(&match?({:ok, _}, Programmes.step_purchase(context, &1.id, :cancel, now)))

    %{completed: completed, cancelled: cancelled}
  end

  defp stale?(context, purchase, now) do
    old? = DateTime.diff(now, purchase.inserted_at, :second) >= @stale_after_seconds
    old? and payment_closed?(context, purchase.payment_intent_id)
  end

  defp payment_closed?(_context, nil), do: true

  defp payment_closed?(context, intent_id) do
    case Payments.get(context, intent_id) do
      {:ok, %{status: status}} -> status in @closed_payments
      {:error, :not_found} -> true
    end
  end
end
