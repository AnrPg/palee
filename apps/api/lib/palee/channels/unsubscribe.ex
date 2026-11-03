defmodule Palee.Channels.Unsubscribe do
  @moduledoc """
  The short link at the end of a marketing SMS (ADR-390): a public page
  where the person withdraws their marketing SMS consent at that box,
  without signing in.

    * `url/1` – the link of a contact, for the SMS text;
    * `find/1` – the box and the contact of a token (signature first, then
      the contact's box through a SECURITY DEFINER lookup, then the
      contact in that box's own tenant session);
    * `withdraw/2` – withdraws the `sms` / `marketing` consent with source
      `unsubscribe_link`, recorded on the consent like every other change
      (ADR-350). Tapping again changes nothing; service messages are not
      touched.
  """

  alias Palee.Channels.{ChannelStore, Contacts}
  alias Palee.Channels.Domain.{ChannelPolicy, UnsubscribeLink}

  @doc "The link a marketing SMS to `contact_id` ends with."
  def url(contact_id) do
    UnsubscribeLink.url(
      Application.fetch_env!(:palee, :public_base_url),
      UnsubscribeLink.sign(key(), contact_id)
    )
  end

  @doc "The token of a contact (tests and support)."
  def token(contact_id), do: UnsubscribeLink.sign(key(), contact_id)

  @doc """
  `{:ok, %{context, contact, withdrawn}}` for a valid token, where
  `withdrawn` says the marketing SMS consent is already off; else
  `{:error, :not_found}`.
  """
  def find(token) do
    with {:ok, contact_id} <- UnsubscribeLink.verify(key(), token),
         organization_id when is_binary(organization_id) <-
           ChannelStore.contact_organization(contact_id),
         context = %{organization_id: organization_id},
         %{} = contact <- Contacts.get(context, contact_id) do
      {:ok, %{context: context, contact: contact, withdrawn: not marketing_on?(contact)}}
    else
      _invalid -> {:error, :not_found}
    end
  end

  @doc "Withdraws the marketing SMS consent of the token's contact: `{:ok, found}` as `find/1`."
  def withdraw(token, %DateTime{} = now) do
    with {:ok, %{context: context, contact: contact} = found} <- find(token) do
      if marketing_on?(contact) do
        {:ok, _consent} =
          ChannelStore.put_consent(context, contact.id, "sms", "marketing", %{
            withdrawn_at: now,
            source: "unsubscribe_link",
            recorded_by_id: nil
          })

        {:ok, %{found | contact: Contacts.get(context, contact.id), withdrawn: true}}
      else
        {:ok, %{found | withdrawn: true}}
      end
    end
  end

  defp marketing_on?(%{opted_out_at: %DateTime{}}), do: false
  defp marketing_on?(contact), do: ChannelPolicy.consented?(contact.consents, "sms", "marketing")

  defp key do
    :palee
    |> Application.fetch_env!(:channels_webhook_key)
    |> UnsubscribeLink.derive_key()
  end
end
