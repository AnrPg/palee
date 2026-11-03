defmodule Palee.Channels do
  @moduledoc """
  SMS, Viber and WhatsApp messages from the box to its members and leads
  (CP-C3, ADR-348..351). Push stays first; these channels are for when
  push is not enough (the person has no app, an urgent cancellation).

  Other contexts and W2's automations use `Palee.Application.Channels.SendThroughChannel`;
  this module is the context's public API for the application layer.

  Palee sends a box's SMS and email by default; the box's own provider is
  the advanced option (ADR-349 for SMS, ADR-368 for email over SMTP). On
  Palee's account the box pays the provider's price plus Palee's margin
  (ADR-369).
  """

  alias Palee.Channels.{Connections, Contacts, EmailConnections, Margins, Sending}

  defdelegate connection(context), to: Connections, as: :get
  defdelegate public_connection(connection), to: Connections, as: :public
  defdelegate provider_catalog, to: Connections, as: :catalog
  defdelegate save_connection(context, params, actor_id), to: Connections, as: :save
  defdelegate check_connection(context, now), to: Connections, as: :check

  # ADR-368: the box's own SMTP email provider.
  defdelegate email_connection(context), to: EmailConnections, as: :get
  defdelegate public_email_connection(connection), to: EmailConnections, as: :public
  defdelegate email_connection_options(connection), to: EmailConnections, as: :options
  defdelegate save_email_connection(context, params, actor_id), to: EmailConnections, as: :save
  defdelegate delete_email_connection(context), to: EmailConnections, as: :delete
  defdelegate check_email_connection(context, now), to: EmailConnections, as: :check
  defdelegate deliver_box_email(context, email), to: EmailConnections, as: :deliver

  # ADR-369: Palee's margin (platform setting) and the box's monthly charge.
  defdelegate margins, to: Margins, as: :get
  defdelegate save_margins(params, actor_id), to: Margins, as: :save
  defdelegate monthly_charge(context, month, env), to: Sending

  defdelegate person(params), to: Contacts
  defdelegate find_contact(context, person), to: Contacts, as: :find
  defdelegate get_contact(context, id), to: Contacts, as: :get
  defdelegate list_contacts(context, filters), to: Contacts, as: :list
  defdelegate save_contact(context, person, params, default_country), to: Contacts, as: :save
  defdelegate set_consent(context, contact_id, params, actor_id, now), to: Contacts
  defdelegate delete_contact(context, id), to: Contacts, as: :delete

  @doc "ADR-211: forgets a person's number, consents and messages in each box (account deletion)."
  def forget_user(organization_ids, user_id) do
    Enum.each(organization_ids, fn organization_id ->
      :ok =
        Palee.Channels.ChannelStore.delete_person(
          %{organization_id: organization_id},
          {:user, user_id}
        )
    end)
  end

  defdelegate public_contact(contact), to: Contacts, as: :public
  defdelegate own_contact(contact), to: Contacts, as: :own

  @doc """
  Whether the person (`%{user_id: id}` or `%{lead_id: id}`) agreed to
  `channel` (`sms`, `viber`, `whatsapp`) for `purpose` (`service`,
  `marketing`) and has not replied STOP.
  """
  def consented?(context, params, channel, purpose) do
    case Contacts.person(params) do
      {:ok, person} -> Contacts.consented?(context, person, channel, purpose)
      {:error, _reason} -> false
    end
  end

  defdelegate list_templates(context), to: Palee.Channels.BoxTemplates, as: :list

  defdelegate save_template(context, key, params, actor_id),
    to: Palee.Channels.BoxTemplates,
    as: :save

  defdelegate delete_template(context, key, locale, channel),
    to: Palee.Channels.BoxTemplates,
    as: :delete

  defdelegate preview(context, request, env), to: Sending
  defdelegate send(context, request, env), to: Sending
  defdelegate deliver(context, which, now), to: Sending
  defdelegate retry(context, id, now), to: Sending
  defdelegate cancel(context, id, actor_id, now), to: Sending
  defdelegate get_message(context, id), to: Sending, as: :get
  defdelegate list_messages(context, filters), to: Sending, as: :list
  defdelegate usage(context, month, env), to: Sending
  defdelegate unit_price(context, channel, purpose), to: Sending
  defdelegate spent_on(context, source_ref), to: Sending
  defdelegate handle_webhook(context, token, request, now), to: Sending

  # ADR-117 reviewed tenant export/purge.
  def tenant_data_policy, do: Palee.Channels.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
