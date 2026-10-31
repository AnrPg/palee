defmodule Palee.Automations.Ports.Channel do
  @moduledoc """
  ADR-346: one way an automatic message reaches a person. Deliberately
  narrow, so the channels of CP-C3 (SMS, Viber, WhatsApp, behind their own
  `MessagingChannel` port and provider credentials) plug in as one more
  adapter, registered in `config :palee, :automation_channels` under their
  name, with no change to recipes or the outbox.

  Adapters today: `in_app` (the bell and push, ADR-199) and `email` (the
  transactional outbox, ADR-203/212).

  `message`:

    * `organization_id`, `delivery_id` (the idempotency key: a retry must
      not send twice), `recipe`, `purpose` (`:service | :marketing`);
    * `recipient` - `%{kind: :member | :lead, organization_id, user_id,
      lead_id, name, email, phone, locale}`;
    * `subject`, `body` (rendered, plain text), `url` (in-app link or nil),
      `box_name`.

  Errors are `{:transient, reason}` (tried again later) or
  `{:permanent, reason}` (this channel will never reach this person for
  this message: the next channel is tried).
  """

  @type recipient :: %{
          required(:kind) => :member | :lead,
          optional(atom()) => term()
        }

  @type message :: %{
          required(:organization_id) => Ecto.UUID.t(),
          required(:delivery_id) => Ecto.UUID.t(),
          required(:recipe) => String.t(),
          required(:recipient) => recipient(),
          required(:subject) => String.t(),
          required(:body) => String.t(),
          optional(atom()) => term()
        }

  @doc "The channel's name, as boxes choose it (`in_app`, `email`, later `sms`, `viber`...)."
  @callback channel() :: String.t()

  @doc "Whether this channel can reach the person at all (an address, an app profile)."
  @callback reachable?(recipient()) :: boolean()

  @callback deliver(message()) ::
              {:ok, String.t() | nil} | {:error, {:transient | :permanent, term()}}
end
