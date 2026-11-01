defmodule Palee.Email.Ports.BoxSender do
  @moduledoc """
  ADR-368: hands a box's own email (a template with `origin: :box`) to the
  box's own SMTP provider. `:unavailable` means the box has none in use
  (not connected, switched off, not checked, or its password was just
  refused): the outbox then sends it through Palee's mailer as before.
  `{:error, reason}` is retried or given up by the outbox like any provider
  error (`DeliveryPolicy.permanent?/1`).
  """

  alias Palee.Email.Ports.Sender

  @callback deliver(organization_id :: Ecto.UUID.t(), Sender.email()) ::
              {:ok, term()} | {:error, term()} | :unavailable
end
