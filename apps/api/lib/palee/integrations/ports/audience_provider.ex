defmodule Palee.Integrations.Ports.AudienceProvider do
  @moduledoc """
  An email-marketing list (ADR-380): Mailchimp audiences, Brevo lists, and
  the sandbox. `connection` is `%{list_id, credentials}` with the API key
  decoded; adapters never log or return it.

  Contacts carry `email` and `first_name` only. `unsubscribe/2` marks the
  address unsubscribed in the list (never deletes it), so the provider keeps
  honouring the member's no.
  """

  @type contact :: %{email: String.t(), first_name: String.t() | nil}
  @type failure :: {:unauthorized, term()} | {:transient, term()} | {:rejected, term()}

  @callback check(connection :: map()) :: :ok | {:error, failure()}
  @callback subscribe(connection :: map(), contact()) :: :ok | {:error, failure()}
  @callback unsubscribe(connection :: map(), email :: String.t()) :: :ok | {:error, failure()}
end
