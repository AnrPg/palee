defmodule Palee.Retention.Ports.SignalReader do
  @moduledoc """
  ADR-347: the facts a risk score is made of, for every active box member
  at once, from the box's own attendance, bookings, subscription packages
  and invoices. A read model over other contexts' tables, in the box's
  scope; it never writes.
  """

  @type context :: map()

  @doc """
  `%{user_id => signals}` (see `Palee.Retention.Domain.RiskScore`) for the
  box's active clients (box members and athletes) on the box's `today`.
  """
  @callback signals(context(), Date.t(), DateTime.t()) :: %{Ecto.UUID.t() => map()}
end
