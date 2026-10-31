defmodule Palee.Channels.Ports.MessagingChannel do
  @moduledoc """
  A messaging provider that sends SMS, Viber or WhatsApp messages and
  reports their delivery (ADR-348 §3). One adapter per provider:
  `Sandbox` (no network; dev, tests and demo boxes) and `Brevo` (SMS; the
  product owner's choice of 2026-10-31). Viber and WhatsApp stay in the
  port for adapters to come (ADR-348 §3 lists the candidates).
  The adapter of each provider comes from `config :palee,
  :channel_providers`.

  `account` holds the decrypted credentials (`account_id`, `secret`,
  `base_url`) and the senders (`sms_sender`, `viber_sender`,
  `whatsapp_sender`): the box's own, or the Palee-managed account's.
  Adapters never log them.

  Errors of `send_message/2` and `check/1`:

    * `{:rejected, detail}` – the provider refused this message (bad
      number, sender not allowed, template not approved): not retried;
    * `{:unauthorized, detail}` – the credentials were refused;
    * `{:transient, detail}` – nothing was sent (network, 429, 5xx);
    * `{:uncertain, detail}` – the call may have reached the provider
      (a timeout): the outbox does not send it again.
  """

  @type account :: %{
          required(:provider) => String.t(),
          optional(:account_id) => String.t() | nil,
          optional(:secret) => String.t() | nil,
          optional(:base_url) => String.t() | nil,
          optional(:sms_sender) => String.t() | nil,
          optional(:viber_sender) => String.t() | nil,
          optional(:whatsapp_sender) => String.t() | nil
        }

  @type outgoing :: %{
          id: Ecto.UUID.t(),
          channel: String.t(),
          to: String.t(),
          body: String.t(),
          purpose: String.t(),
          template: nil | %{provider_template_id: String.t(), locale: String.t(), values: [String.t()]},
          callback_url: String.t() | nil
        }

  @type accepted :: %{
          required(:provider_message_id) => String.t(),
          optional(:cost_cents) => non_neg_integer() | nil,
          optional(:currency) => String.t() | nil
        }

  @type error_kind :: :rejected | :unauthorized | :transient | :uncertain

  @typedoc """
  A webhook call: the full URL it was posted to, its decoded params, its
  headers (lower-case names) and raw body.
  """
  @type request :: %{url: String.t(), params: map(), headers: [{String.t(), String.t()}], raw_body: String.t()}

  @typedoc """
  What a webhook reports: a delivery receipt (`status` one of `sent`,
  `delivered`, `failed`) or an inbound text (only used for STOP words,
  never stored).
  """
  @type event ::
          %{
            type: :status,
            provider_message_id: String.t(),
            status: String.t(),
            provider_status: String.t() | nil,
            error_code: String.t() | nil,
            cost_cents: non_neg_integer() | nil,
            currency: String.t() | nil,
            occurred_at: DateTime.t() | nil,
            event_key: String.t()
          }
          | %{type: :inbound, channel: String.t(), from: String.t(), text: String.t()}

  @callback send_message(account(), outgoing()) :: {:ok, accepted()} | {:error, {error_kind(), term()}}

  @doc "«Δοκιμή σύνδεσης»: a harmless authenticated call (balance or account)."
  @callback check(account()) :: {:ok, map()} | {:error, {error_kind(), term()}}

  @doc "Verifies the provider's signature and reads the events of a webhook call."
  @callback parse_webhook(account(), request()) :: {:ok, [event()]} | {:error, :invalid_signature}

  @doc "The channels this provider can send through."
  @callback channels() :: [String.t()]
end
