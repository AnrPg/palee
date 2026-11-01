defmodule Palee.Channels.Ports.ChannelStore do
  @moduledoc """
  Persistence of the Channels context (ADR-348). Every callback takes the
  tenant context first; the facade runs it inside a `RepoContext` session,
  so row-level security confines it to the box.

  Claiming moves due messages to `sending` and spends one attempt in one
  statement (`FOR UPDATE SKIP LOCKED`), so two workers never send the same
  message; `update_message/4` records the change and its event together.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()
  @type person :: {:user, id()} | {:lead, id()}

  @callback transaction(context(), (-> term())) :: term()

  # Connection
  @callback get_connection(context()) :: map() | nil
  @callback save_connection(context(), map()) :: {:ok, map()} | {:error, term()}

  # ADR-368: the box's own SMTP email provider
  @callback get_email_connection(context()) :: map() | nil
  @callback save_email_connection(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_email_connection(context()) :: :ok

  # ADR-369: the installation's settings (platform data, no tenant)
  @callback get_platform_settings() :: map() | nil
  @callback save_platform_settings(map()) :: {:ok, map()} | {:error, term()}

  # Contacts and consents
  @callback get_contact(context(), id()) :: map() | nil
  @callback find_contact(context(), person()) :: map() | nil
  @callback save_contact(context(), person(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_contact(context(), id()) :: :ok
  @doc "Deletes the person's contact (with its consents and messages), if any."
  @callback delete_person(context(), person()) :: :ok
  @callback contacts_by_phone(context(), String.t()) :: [map()]
  @callback list_contacts(context(), map()) :: [map()]
  @callback list_consents(context(), [id()]) :: [map()]
  @callback put_consent(context(), id(), String.t(), String.t(), map()) ::
              {:ok, map()} | {:error, term()}

  # Templates
  @callback list_templates(context(), String.t() | nil) :: [map()]
  @callback save_template(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_template(context(), String.t(), String.t(), String.t()) :: :ok

  # Outbox
  @callback insert_message(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_message(context(), id()) :: map() | nil
  @callback get_message_by_key(context(), String.t()) :: map() | nil
  @callback get_message_by_provider_id(context(), String.t(), String.t()) :: map() | nil
  @callback claim(context(), :due | id(), DateTime.t(), pos_integer()) :: [map()]
  @callback update_message(context(), id(), map(), map() | nil) :: {:ok, map()} | {:error, term()}
  @doc "Records a receipt once: `{:ok, :duplicate}` when its `event_key` was seen."
  @callback record_event(context(), map()) :: {:ok, map() | :duplicate} | {:error, term()}
  @callback list_messages(context(), map()) :: %{messages: [map()], total: non_neg_integer()}
  @callback list_events(context(), id()) :: [map()]
  @doc """
  What the box spent between two instants (cents): `%{total, by_channel,
  count}` in the box's price, plus `palee_charge` (the box price of
  messages sent on Palee's account, what Palee bills) and `provider_total`
  (the providers' price of those, for the Palee team only), ADR-369.
  """
  @callback spend(context(), DateTime.t(), DateTime.t()) :: map()
end
