defmodule Palee.Application.Channels.BoxEmailSender do
  @moduledoc """
  ADR-368: the email outbox's `BoxSender` (`config :palee, :email_box_sender`).
  A box's own email goes through the box's own SMTP provider when it has one
  connected, switched on and checked; `:unavailable` sends it through
  Palee's mailer instead. Runs as the system for the box (a job), under the
  box's row-level security.
  """

  @behaviour Palee.Email.Ports.BoxSender

  alias Palee.Channels

  @impl true
  def deliver(organization_id, email),
    do: Channels.deliver_box_email(%{organization_id: organization_id}, email)
end
