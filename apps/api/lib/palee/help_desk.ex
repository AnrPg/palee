defmodule Palee.HelpDesk do
  @moduledoc """
  In-app support for a box's staff with an AI first line (ADR-363): the
  assistant answers from help-centre articles only, with citations, and
  hands the conversation to the Palee team as a ticket when it cannot.
  """

  alias Palee.HelpDesk.Domain.{Assistant, ConversationPolicy}
  alias Palee.HelpDesk.HelpDeskStore

  defdelegate statuses(), to: ConversationPolicy
  defdelegate ticket_statuses(), to: ConversationPolicy
  defdelegate priorities(), to: ConversationPolicy
  defdelegate validate_message(text), to: ConversationPolicy, as: :message
  defdelegate screen(path), to: ConversationPolicy
  defdelegate subject(text), to: ConversationPolicy
  defdelegate after_person_message(conversation, has_ticket?), to: ConversationPolicy
  defdelegate assistant_turn?(status), to: ConversationPolicy
  defdelegate new_ticket(conversation, messages, params), to: ConversationPolicy, as: :ticket
  defdelegate ticket_update(ticket, params, now), to: ConversationPolicy
  defdelegate conversation_status_for_ticket(status), to: ConversationPolicy

  defdelegate assistant_system(facts), to: Assistant, as: :system
  defdelegate assistant_documents(articles), to: Assistant, as: :documents
  defdelegate assistant_turns(messages), to: Assistant, as: :turns
  defdelegate assistant_schema(), to: Assistant, as: :answer_schema
  defdelegate evaluate_answer(json, articles), to: Assistant, as: :evaluate

  defdelegate create_conversation(context, attrs), to: HelpDeskStore
  defdelegate get_conversation(context, id), to: HelpDeskStore
  defdelegate list_conversations(context, user_id), to: HelpDeskStore
  defdelegate update_conversation(context, id, changes), to: HelpDeskStore
  defdelegate add_message(context, attrs), to: HelpDeskStore
  defdelegate list_messages(context, id), to: HelpDeskStore
  defdelegate count_person_messages_since(context, user_id, since), to: HelpDeskStore
  defdelegate create_ticket(context, attrs), to: HelpDeskStore
  defdelegate ticket_for_conversation(context, id), to: HelpDeskStore
  defdelegate update_ticket(context, id, changes), to: HelpDeskStore
  defdelegate list_tickets(vendor, filters), to: HelpDeskStore
  defdelegate get_ticket(vendor, id), to: HelpDeskStore

  # ADR-117 reviewed tenant export/purge.
  def tenant_data_policy, do: Palee.HelpDesk.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
