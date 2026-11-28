defmodule Palee.Application.ActivityLogDigest do
  @moduledoc """
  ADR-760 (ANR 12B): every morning, the box's owners hear what sensitive
  actions the staff did the day before (forgiven charges, credit notes,
  statuses and package end dates set by hand, gifts …): how many of each
  kind, with the way to «Αρχείο ενεργειών» filtered to them. A bell
  notification with its push (`activity_log_digest`, staff category) and an
  email, in each owner's language. A day without sensitive actions sends
  nothing.

  `run/2` is for one box (the hourly `ActivityLogDigestJob` calls it for
  each). It reads only that box's rows, in its own repo scope. Before the
  box's morning hour it does nothing; after it, it sends yesterday's
  summary once: the notification's dedupe key and the email's idempotency
  key carry the box and the day, so later runs that day add nothing.
  """

  require Logger

  alias Palee.ActivityLog
  alias Palee.ActivityLog.Domain.OwnerDigest
  alias Palee.Application.PublicURL
  alias Palee.{Email, Identity, Localization, Notifications, Organizations}

  @domain "activity_log"

  @doc """
  Sends yesterday's summary of one box (`context` carries its id) to its
  owners. `{:ok, owners_reached}`, `:not_yet` before the morning hour, or
  `:nothing` when the day had no sensitive action.
  """
  def run(%{organization_id: organization_id}, now \\ DateTime.utc_now())
      when is_binary(organization_id) do
    zone = Organizations.organization_timezone(organization_id)

    with {:ok, day} <- OwnerDigest.due_day(now, zone),
         {from, to} = OwnerDigest.window(day, zone),
         entries = ActivityLog.sensitive_between(%{organization_id: organization_id}, from, to),
         [_ | _] = counts <- OwnerDigest.counts(entries) do
      box = Organizations.brand_summary(organization_id) || %{name: "", slug: nil}

      owners = Organizations.list_owner_user_ids(organization_id)
      Enum.each(owners, &send_to(&1, organization_id, box, day, counts, now))
      {:ok, length(owners)}
    else
      :not_yet -> :not_yet
      [] -> :nothing
    end
  end

  defp send_to(user_id, organization_id, box, day, counts, now) do
    account = Identity.find_by_id(user_id)
    locale = (account && Map.get(account, :preferred_locale)) || "en"
    total = OwnerDigest.total(counts)
    path = OwnerDigest.path(day)
    key = OwnerDigest.key(organization_id, day)

    notify(%{
      user_id: user_id,
      organization_id: organization_id,
      date: day,
      total: total,
      counts: Enum.map(counts, &Map.take(&1, [:action, :count])),
      title: title(locale, box.name, total),
      body: Enum.join(lines(locale, counts), " · "),
      url: path,
      dedupe_key: key
    })

    email(account, organization_id, "#{key}:#{user_id}",
      box: box.name,
      date: day,
      total: total,
      lines: lines(locale, counts),
      url: web_url(box.slug, path),
      now: now
    )
  end

  @doc "The title of the summary in `locale`: the box and how many actions."
  def title(locale, box, total) do
    Localization.translate_plural(
      locale,
      "%{box}: %{count} sensitive action yesterday",
      "%{box}: %{count} sensitive actions yesterday",
      total,
      %{box: box || ""},
      @domain
    )
  end

  @doc "One line per kind, in `locale`: «Πιστωτικά: 2»."
  def lines(locale, counts) do
    Enum.map(counts, fn %{action: action, count: count} ->
      Localization.translate(
        locale,
        "%{label}: %{count}",
        %{
          label: Localization.translate(locale, OwnerDigest.label(action), %{}, @domain),
          count: count
        },
        @domain
      )
    end)
  end

  defp notify(payload) do
    case Notifications.process_event("activity_log_digest", payload) do
      {:error, reason} ->
        Logger.warning("activity_log_digest notice not stored: #{inspect(reason)}")

      _stored ->
        :ok
    end
  end

  defp email(%{email: address} = account, organization_id, key, assigns)
       when is_binary(address) do
    {now, assigns} = Keyword.pop(assigns, :now)

    case Email.enqueue(:activity_log_digest, address, Map.new(assigns),
           locale: Map.get(account, :preferred_locale) || "en",
           login_id: Map.get(account, :login_id),
           user_id: account.id,
           organization_id: organization_id,
           idempotency_key: key,
           now: now
         ) do
      {:error, reason} ->
        Logger.warning("activity_log_digest email not queued: #{inspect(reason)}")

      _queued ->
        :ok
    end
  end

  defp email(_account, _organization_id, _key, _assigns), do: :ok

  defp web_url(slug, path) when is_binary(slug),
    do: PublicURL.base_url() <> "/org/#{slug}" <> path

  defp web_url(_slug, path), do: PublicURL.base_url() <> path
end
