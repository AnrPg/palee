defmodule Palee.Application.Integrations.ConnectionNotices do
  @moduledoc """
  What the staff who manage settings (`manage_settings`: owners and admins)
  hear about the box's connections (ADR-378/379, 2026-11-03):

    * `webhook_disabled/3` – Palee turned off a webhook that kept failing
      (or answered 410, or now points at a private address): a bell
      notification and an email, each with the way to the webhook's page;
    * `api_key_created/3` – a new API key exists: an email naming the key,
      who made it and when, so a key made without them is seen. It never
      carries the key.

  Both go through the email outbox (ADR-203) with idempotency keys, so a
  retried job never sends twice, and never fail the action that caused them.
  """

  require Logger

  alias Palee.Application.PublicURL
  alias Palee.{Email, Identity, Notifications, Organizations}
  alias Palee.TimeZones.ZonedTime

  @doc "The webhook `endpoint` (`id`, `url`, `reason`) was turned off by Palee."
  def webhook_disabled(%{organization_id: organization_id}, endpoint, %DateTime{} = now) do
    box = Organizations.brand_summary(organization_id) || %{name: "", slug: nil}
    path = "/admin/settings/webhooks/#{endpoint.id}"
    stamp = DateTime.to_unix(now)

    for user_id <- recipients(organization_id) do
      notify(user_id, %{
        host: host(endpoint.url),
        reason: endpoint.reason,
        url: path,
        dedupe_key: "webhook_disabled:#{endpoint.id}:#{stamp}:#{user_id}"
      })

      email(
        user_id,
        :webhook_disabled,
        organization_id,
        "webhook_disabled:#{endpoint.id}:#{stamp}",
        url: web_url(box.slug, path),
        box: box.name,
        host: host(endpoint.url),
        reason: endpoint.reason,
        now: now
      )
    end

    :ok
  rescue
    error -> failed(:webhook_disabled, error)
  end

  @doc "A new API key `key` (its view, without the token) was made."
  def api_key_created(%{organization_id: organization_id}, key, %DateTime{} = now) do
    box = Organizations.brand_summary(organization_id) || %{name: "", slug: nil}
    maker = key.created_by_id && Identity.find_by_id(key.created_by_id)
    zone = Organizations.organization_timezone(organization_id)

    for user_id <- recipients(organization_id) do
      email(user_id, :api_key_created, organization_id, "api_key_created:#{key.id}",
        url: web_url(box.slug, "/admin/settings?connections=keys#connections"),
        box: box.name,
        name: key.name,
        masked: key.masked,
        scopes: Enum.join(key.scopes, ", "),
        maker: (maker && Map.get(maker, :nickname)) || "",
        at: now |> ZonedTime.local(zone) |> Calendar.strftime("%d/%m/%Y %H:%M"),
        now: now
      )
    end

    :ok
  rescue
    error -> failed(:api_key_created, error)
  end

  defp recipients(organization_id),
    do: Organizations.list_user_ids_with_capability(organization_id, :manage_settings)

  defp notify(user_id, payload) do
    case Notifications.process_event("webhook_disabled", Map.put(payload, :user_id, user_id)) do
      {:error, reason} -> Logger.warning("webhook_disabled notice not stored: #{inspect(reason)}")
      _stored -> :ok
    end
  end

  defp email(user_id, kind, organization_id, key, assigns) do
    {now, assigns} = Keyword.pop(assigns, :now)

    with %{email: address} = account when is_binary(address) <- Identity.find_by_id(user_id),
         {:error, reason} <-
           Email.enqueue(kind, address, Map.new(assigns),
             locale: Map.get(account, :preferred_locale) || "en",
             login_id: Map.get(account, :login_id),
             user_id: user_id,
             organization_id: organization_id,
             idempotency_key: "#{key}:#{user_id}",
             now: now
           ) do
      Logger.warning("#{kind} email not queued: #{inspect(reason)}")
    end

    :ok
  end

  defp host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _unparsed -> url
    end
  end

  defp host(_url), do: ""

  defp web_url(slug, path) when is_binary(slug),
    do: PublicURL.base_url() <> "/org/#{slug}" <> path

  defp web_url(_slug, path), do: PublicURL.base_url() <> path

  defp failed(kind, error) do
    Logger.error("#{kind} notice failed: #{Exception.message(error)}")
    :ok
  end
end
