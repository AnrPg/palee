defmodule Palee.HelpDesk.Ports.HelpDeskStore do
  @moduledoc """
  Persistence of support conversations, messages and tickets (ADR-363).
  Box calls take the tenant context first. The Palee team's queue
  (`list_tickets/2`, `get_ticket/2`) runs in the vendor's own session,
  whose row policy admits every box's tickets and nothing else.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback create_conversation(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_conversation(context(), id()) :: map() | nil
  @callback list_conversations(context(), user_id :: id()) :: [map()]
  @callback update_conversation(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback add_message(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_messages(context(), conversation_id :: id()) :: [map()]
  @callback count_person_messages_since(context(), user_id :: id(), DateTime.t()) ::
              non_neg_integer()
  @callback create_ticket(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback ticket_for_conversation(context(), conversation_id :: id()) :: map() | nil
  @callback update_ticket(context(), id(), map()) :: {:ok, map()} | {:error, term()}

  @doc "Every box's tickets, newest first, filtered by `status`."
  @callback list_tickets(vendor :: context(), filters :: map()) :: [map()]
  @callback get_ticket(vendor :: context(), id()) :: map() | nil
end
