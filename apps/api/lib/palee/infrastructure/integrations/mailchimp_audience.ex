defmodule Palee.Infrastructure.Integrations.MailchimpAudience do
  @moduledoc """
  Mailchimp Marketing API 3.0 (ADR-380;
  https://mailchimp.com/developer/marketing/api/list-members/).

    * the API key ends with the data centre (`…-us21`), which names the
      host `https://us21.api.mailchimp.com/3.0`; basic auth `palee:<key>`;
    * subscribe: `PUT /lists/{list_id}/members/{md5(lower email)}` with
      `status_if_new: subscribed`, `status: subscribed` and `FNAME`
      (an upsert, so running twice is harmless);
    * unsubscribe: `PATCH` the same member with `status: unsubscribed`;
      a 404 (never in the list) is already the wanted state;
    * check: `GET /lists/{list_id}?fields=id`.

  Members said yes inside Palee, so no double opt-in email is sent; the
  consent record (time, text version) is Palee's proof.
  """

  @behaviour Palee.Integrations.Ports.AudienceProvider

  alias Palee.Infrastructure.Integrations.AudienceHttp
  alias Palee.Integrations.Domain.AudienceSyncPlan

  @impl true
  def check(connection) do
    with {:ok, base} <- base(connection),
         {:ok, _response} <-
           AudienceHttp.request(
             method: :get,
             url: "#{base}/lists/#{connection.list_id}",
             params: [fields: "id"],
             auth: auth(connection)
           ),
         do: :ok
  end

  @impl true
  def subscribe(connection, contact) do
    body = %{
      email_address: AudienceSyncPlan.normalize_email(contact.email),
      status_if_new: "subscribed",
      status: "subscribed",
      merge_fields: %{FNAME: contact.first_name || ""}
    }

    with {:ok, base} <- base(connection),
         {:ok, _response} <-
           AudienceHttp.request(
             method: :put,
             url: member_url(base, connection, contact.email),
             json: body,
             auth: auth(connection)
           ),
         do: :ok
  end

  @impl true
  def unsubscribe(connection, email) do
    with {:ok, base} <- base(connection) do
      case AudienceHttp.request(
             method: :patch,
             url: member_url(base, connection, email),
             json: %{status: "unsubscribed"},
             auth: auth(connection)
           ) do
        {:ok, _response} -> :ok
        {:error, {:rejected, {:http, 404, _detail}}} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp member_url(base, connection, email),
    do:
      "#{base}/lists/#{connection.list_id}/members/#{AudienceSyncPlan.mailchimp_subscriber_hash(email)}"

  defp base(%{credentials: %{"api_key" => key}}) when is_binary(key) do
    case String.split(key, "-") do
      [_secret, dc] when dc != "" ->
        if dc =~ ~r/\A[a-z]{2,4}[0-9]{1,3}\z/,
          do: {:ok, "https://#{dc}.api.mailchimp.com/3.0"},
          else: {:error, {:unauthorized, :invalid_api_key}}

      _other ->
        {:error, {:unauthorized, :invalid_api_key}}
    end
  end

  defp base(_connection), do: {:error, {:unauthorized, :missing_api_key}}

  defp auth(%{credentials: %{"api_key" => key}}), do: {:basic, "palee:" <> key}
end
