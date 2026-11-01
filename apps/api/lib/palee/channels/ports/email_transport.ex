defmodule Palee.Channels.Ports.EmailTransport do
  @moduledoc """
  Sending a box's email through its own SMTP provider (ADR-368).

  `smtp` carries the connection with its decrypted password: `host`, `port`,
  `tls_mode` (`starttls` | `tls`), `username`, `secret`, `from_address`,
  `from_name`, `reply_to`. An adapter never logs the password and never
  raises: every outcome is a return value.

  `check/1` («Δοκιμή σύνδεσης») connects, upgrades to TLS and logs in, then
  quits without sending anything.

  Errors:

    * `:unauthorized` – the provider refused the user name or password (the
      connection is marked invalid; the email falls back to Palee);
    * `:host_not_allowed` – the host resolves to a private or reserved
      address;
    * `{:permanent_failure, detail}` – the provider refused this email for
      good (an SMTP 5xx, e.g. an unknown recipient): not retried;
    * `{:transient, detail}` – anything else (unreachable, timeout, TLS
      failure, a 4xx): retried by the email outbox.
  """

  @type smtp :: %{
          required(:host) => String.t(),
          required(:port) => pos_integer(),
          required(:tls_mode) => String.t(),
          required(:username) => String.t(),
          required(:secret) => String.t(),
          required(:from_address) => String.t(),
          optional(:from_name) => String.t() | nil,
          optional(:reply_to) => String.t() | nil
        }

  # The rendered email of the outbox (`Palee.Email.Ports.Sender.email/0`).
  @type email :: %{
          required(:to) => String.t(),
          required(:subject) => String.t(),
          required(:text) => String.t(),
          required(:html) => String.t(),
          required(:message_id) => String.t(),
          optional(:headers) => %{String.t() => String.t()},
          optional(:attachments) => [map()]
        }

  @type error ::
          :unauthorized
          | :host_not_allowed
          | {:permanent_failure, term()}
          | {:transient, term()}

  @callback check(smtp()) :: {:ok, map()} | {:error, error()}
  @callback deliver(smtp(), email()) :: {:ok, term()} | {:error, error()}
end
