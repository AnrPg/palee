defmodule Palee.Infrastructure.Integrations.BrevoAudience do
  @moduledoc """
  Brevo contacts API v3 (ADR-380; https://developers.brevo.com/reference/createcontact).

    * subscribe: `POST /v3/contacts` with `{email, attributes: {FIRSTNAME},
      listIds: [list], updateEnabled: true}` (an upsert);
    * unsubscribe: `POST /v3/contacts/lists/{list}/contacts/remove` with
      `{emails: [email]}`; Brevo keeps the contact, so a later import
      cannot silently add the member back to the list;
    * check: `GET /v3/contacts/lists/{list}`.

  Header `api-key`. This is the box's own Brevo account, separate from the
  platform's transactional Brevo (ADR-212).
  """

  @behaviour Palee.Integrations.Ports.AudienceProvider

  alias Palee.Infrastructure.Integrations.AudienceHttp
  alias Palee.Integrations.Domain.AudienceSyncPlan

  @base "https://api.brevo.com/v3"

  @impl true
  def check(connection) do
    with {:ok, list_id} <- list_id(connection),
         {:ok, _response} <-
           AudienceHttp.request(
             method: :get,
             url: "#{@base}/contacts/lists/#{list_id}",
             headers: headers(connection)
           ),
         do: :ok
  end

  @impl true
  def subscribe(connection, contact) do
    with {:ok, list_id} <- list_id(connection),
         {:ok, _response} <-
           AudienceHttp.request(
             method: :post,
             url: "#{@base}/contacts",
             headers: headers(connection),
             json: %{
               email: AudienceSyncPlan.normalize_email(contact.email),
               attributes: %{FIRSTNAME: contact.first_name || ""},
               listIds: [list_id],
               updateEnabled: true
             }
           ),
         do: :ok
  end

  @impl true
  def unsubscribe(connection, email) do
    with {:ok, list_id} <- list_id(connection) do
      case AudienceHttp.request(
             method: :post,
             url: "#{@base}/contacts/lists/#{list_id}/contacts/remove",
             headers: headers(connection),
             json: %{emails: [AudienceSyncPlan.normalize_email(email)]}
           ) do
        {:ok, _response} -> :ok
        {:error, {:rejected, {:http, status, _detail}}} when status in [400, 404] -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp list_id(%{list_id: list_id}) do
    case Integer.parse(to_string(list_id)) do
      {id, ""} when id > 0 -> {:ok, id}
      _invalid -> {:error, {:rejected, :invalid_list_id}}
    end
  end

  defp headers(%{credentials: %{"api_key" => key}}),
    do: [{"api-key", key}, {"accept", "application/json"}]

  defp headers(_connection), do: [{"accept", "application/json"}]
end
