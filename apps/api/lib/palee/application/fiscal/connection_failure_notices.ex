defmodule Palee.Application.Fiscal.ConnectionFailureNotices do
  @moduledoc """
  `Fiscal.Ports.ConnectionNotifier` over Notifications (ADR-273, ADR-530): every
  staff member who manages billing hears that a fiscal connection stopped
  working, with a link to «Στοιχεία τιμολόγησης › Συνδέσεις». At most once
  a day per connection and person, so a retried job never notifies twice.
  """

  @behaviour Palee.Fiscal.Ports.ConnectionNotifier

  require Logger

  alias Palee.{Notifications, Organizations}

  # Brand and service names, the same in every language (ontology §4.16).
  @names %{
    "mydata" => "myDATA",
    "registry" => "AADE",
    "tse" => "fiskaly SIGN DE",
    "rksv" => "fiskaly SIGN AT",
    "sign_fr" => "fiskaly SIGN FR",
    "peppol" => "fiskaly E-INVOICE"
  }

  def name(kind), do: Map.get(@names, kind, kind)

  @impl true
  def connection_failed(%{organization_id: organization_id}, kind, code) do
    today = Date.to_iso8601(Date.utc_today())

    organization_id
    |> Organizations.list_user_ids_with_capability(:manage_billing)
    |> Enum.each(fn user_id ->
      deliver(user_id, %{
        connection: name(kind),
        error_code: code,
        url: "/admin/settings/billing?connection=#{kind}",
        dedupe_key: "fiscal_connection_failed:#{organization_id}:#{kind}:#{today}:#{user_id}"
      })
    end)

    :ok
  end

  @doc """
  ADR-530: documents that did not reach the authority (refused, or out of
  attempts) and wait for staff, with a link to «Παραστατικά». At most once
  a day per connection and person; the count is of this run.
  """
  @impl true
  def documents_not_reported(%{organization_id: organization_id}, kind, count) do
    today = Date.to_iso8601(Date.utc_today())

    organization_id
    |> Organizations.list_user_ids_with_capability(:manage_billing)
    |> Enum.each(fn user_id ->
      deliver("fiscal_documents_not_reported", user_id, %{
        connection: name(kind),
        count: count,
        url: "/admin/finance?tab=documents",
        dedupe_key: "fiscal_documents_not_reported:#{organization_id}:#{kind}:#{today}:#{user_id}"
      })
    end)

    :ok
  end

  defp deliver(user_id, payload), do: deliver("fiscal_connection_failed", user_id, payload)

  defp deliver(type, user_id, payload) do
    Notifications.process_event(type, Map.put(payload, :user_id, user_id))
  rescue
    error ->
      Logger.warning("fiscal_connection_notice_failed reason=#{Exception.message(error)}")
      :ok
  end
end
