defmodule Palee.Access.Ports.DoorController do
  @moduledoc """
  A door controller (ADR-381): what Palee asks of the box's lock, relay or
  access system. One adapter per provider (`sandbox`, `shelly`, `kisi`),
  chosen by `config :palee, :door_controllers`.

  `controller` is `%{id, provider, settings, credentials, rules}` with the
  credentials decoded; adapters never log or return them.

    * `unlock/2` opens the door for `seconds` (a pulse). It answers quickly
      (a short timeout) and never retries by itself: a door that opens a
      minute late is worse than one that does not open. `{:error,
      {:offline, reason}}` means the controller could not be reached; the
      door stays locked (fail-secure) and the member is sent to the desk.
    * `check/1` proves the settings and credentials work, without opening.
    * `parse_event/2` turns the provider's own notification (a Shelly
      action URL, a Kisi webhook) into door events for the access log.
  """

  @type controller :: %{
          required(:provider) => String.t(),
          required(:settings) => map(),
          required(:credentials) => map(),
          optional(atom()) => term()
        }

  @type failure ::
          {:offline, term()} | {:unauthorized, term()} | {:rejected, term()}

  @callback unlock(controller(), seconds :: pos_integer()) :: :ok | {:error, failure()}
  @callback check(controller()) :: :ok | {:error, failure()}
  @callback parse_event(controller(), params :: map()) ::
              {:ok, [%{event: String.t(), occurred_at: DateTime.t() | nil}]}
              | {:error, :invalid_event}
end
