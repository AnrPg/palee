defmodule Palee.Notifications.Commands.CreateNotification do
  @moduledoc """
  Writes an in-app notification (the push follows it). ADR-184: a mock
  person of a demo business never gets one, and a demo business notifies
  nobody outside its own staff. ADR-199: a person who switched the type's
  category off for the bell does not get it either. Either way the answer is
  `{:ok, :suppressed}` and nothing is written or pushed.

  Every in-app notification is written here, so this is where the bell
  preference is checked, and where it gets its `group_key` (ADR-600): the
  key of its stack of similar notifications, by
  `Domain.NotificationGrouping`, with "today" on the box's clock (ADR-176)
  or, for a notification without a box, on the recipient's.
  """

  alias Palee.BusinessAccounts
  alias Palee.Identity
  alias Palee.Notifications.Domain.NotificationGrouping
  alias Palee.Notifications.NotificationStore
  alias Palee.Notifications.Queries.DeliversNotification
  alias Palee.Organizations
  alias Palee.TimeZones.ZonedTime

  def call(params, now \\ DateTime.utc_now()) do
    if suppressed?(params) or muted?(params),
      do: {:ok, :suppressed},
      else: params |> put_group_key(now) |> NotificationStore.create_notification()
  end

  # A caller may name the key itself (tests, a backfill); else the rule decides.
  defp put_group_key(params, now) do
    if Map.has_key?(params, :group_key) or Map.has_key?(params, "group_key") do
      params
    else
      type = field(params, :type)
      organization_id = field(params, :organization_id)
      rule = NotificationGrouping.rule(type)

      local_day =
        case NotificationGrouping.day_zone(rule, organization_id) do
          :none ->
            nil

          :organization ->
            ZonedTime.local_date(now, Organizations.organization_timezone(organization_id))

          :recipient ->
            ZonedTime.local_date(now, recipient_zone(field(params, :user_id)))
        end

      Map.put(
        params,
        :group_key,
        NotificationGrouping.key(type, field(params, :payload), organization_id, local_day)
      )
    end
  end

  defp recipient_zone(user_id) when is_binary(user_id) do
    case Identity.find_by_id(user_id) do
      nil -> ZonedTime.default_zone()
      account -> Identity.time_zone(account)
    end
  end

  defp recipient_zone(_user_id), do: ZonedTime.default_zone()

  defp suppressed?(params) do
    BusinessAccounts.notification_suppressed?(
      field(params, :organization_id),
      field(params, :user_id)
    )
  end

  defp muted?(params),
    do: not DeliversNotification.call(field(params, :user_id), field(params, :type), "in_app")

  defp field(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
