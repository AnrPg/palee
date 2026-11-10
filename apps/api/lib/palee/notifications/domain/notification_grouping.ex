defmodule Palee.Notifications.Domain.NotificationGrouping do
  @moduledoc """
  ADR-600: which notifications are "similar", so the inbox shows them as one
  stack («+14 ακόμη παρόμοιες») and the phone keeps one push for them that
  updates itself instead of fifteen.

  Every notification gets a `group_key` when it is written. Notifications
  with the same key are similar. Nothing is merged or dropped: each one is
  still its own row that can be read, opened or deleted; the key only says
  how the inbox and the push show them.

  The rule of a type:

    * `:day` (the default, so a new type is stacked without any change here):
      same type, same box, same day on the box's clock (the recipient's clock
      when the notification has no box).
    * `{:conversation, field}`: messages stack per conversation, whatever the
      day (`field` names the conversation in the payload).
    * `:personal_day`: same type, same day on the recipient's clock, any box
      (people following me).
    * `{:subject_day, field}`: same type and box, same day of the thing it is
      about (the WOD's day), else the day it arrived.
    * `:never`: always on its own (account security).

  The backfill migration `20271112100000_notification_group_key` writes the
  same keys in SQL for the rows written before this; a change of a rule here
  needs no change there (old rows keep the key they were written with).

  Pure: the caller resolves the day on the right clock (`day_zone/2`).
  """

  @min_stack_size 3
  @max_part_length 120

  @conversation_rules %{
    "chat_message" => "thread_id",
    "coaching_message" => "thread_id",
    "box_message" => "thread_id",
    "box_inbox_message" => "thread_id",
    "person_message" => "conversation_id",
    "message_request" => "conversation_id",
    "buddy_message" => "link_id",
    "partner_message" => "match_id",
    "support_reply" => "request_id",
    "community_event_message" => "event_id"
  }

  @personal_day_types ~w(follow_requested new_follower follow_accepted)

  @subject_day_rules %{
    "workout_changed" => "scheduled_for",
    "workout_note" => "scheduled_for",
    "workout_moved" => "scheduled_for"
  }

  @never_types ~w(password_reset_requested password_reset_completed)

  @type rule ::
          :day
          | :personal_day
          | :never
          | {:conversation, String.t()}
          | {:subject_day, String.t()}

  @doc "A stack shows from this many similar notifications on; fewer show one by one."
  def min_stack_size, do: @min_stack_size

  @doc "The grouping rule of a notification type."
  @spec rule(atom() | String.t()) :: rule()
  def rule(type) when is_atom(type), do: rule(Atom.to_string(type))

  def rule(type) when is_binary(type) do
    cond do
      type in @never_types -> :never
      Map.has_key?(@conversation_rules, type) -> {:conversation, @conversation_rules[type]}
      type in @personal_day_types -> :personal_day
      Map.has_key?(@subject_day_rules, type) -> {:subject_day, @subject_day_rules[type]}
      true -> :day
    end
  end

  @doc """
  Whose clock decides "the same day": `:organization` for a notification of a
  box (the box's zone, ADR-176), `:recipient` otherwise, `:none` when the rule
  has no day. A message's rule needs the day too: without its conversation it
  falls back to the day.
  """
  @spec day_zone(rule(), String.t() | nil) :: :organization | :recipient | :none
  def day_zone(:never, _organization_id), do: :none
  def day_zone(:personal_day, _organization_id), do: :recipient
  def day_zone(_rule, organization_id) when is_binary(organization_id), do: :organization
  def day_zone(_rule, _organization_id), do: :recipient

  @doc """
  The notification's group key, or nil when it never stacks. `local_day` is
  today on the clock `day_zone/2` names (ignored by rules without a day).
  """
  @spec key(atom() | String.t(), map(), String.t() | nil, Date.t() | nil) :: String.t() | nil
  def key(type, payload, organization_id, local_day) do
    type = to_string(type)
    payload = payload || %{}

    case rule(type) do
      :never ->
        nil

      {:conversation, field} ->
        case part(field(payload, field)) do
          nil -> day_key(type, organization_id, local_day)
          conversation -> Enum.join([type, "c", conversation], ":")
        end

      :personal_day ->
        if local_day, do: Enum.join([type, "p", "d", Date.to_iso8601(local_day)], ":")

      {:subject_day, field} ->
        day_key(type, organization_id, subject_day(field(payload, field)) || local_day)

      :day ->
        day_key(type, organization_id, local_day)
    end
  end

  @doc """
  The tag a push carries so the phone replaces the earlier push of the same
  stack instead of adding one (web push `tag`, Android `tag`, APNs
  `apns-collapse-id`, which allows at most 64 bytes). Nil without a key.
  """
  @spec push_tag(String.t() | nil) :: String.t() | nil
  def push_tag(nil), do: nil
  def push_tag(""), do: nil

  def push_tag(group_key) when is_binary(group_key) do
    digest = :crypto.hash(:sha256, group_key) |> Base.encode16(case: :lower)
    "palee-" <> binary_part(digest, 0, 32)
  end

  defp day_key(_type, _organization_id, nil), do: nil

  defp day_key(type, organization_id, %Date{} = day),
    do: Enum.join([type, "o", part(organization_id) || "-", "d", Date.to_iso8601(day)], ":")

  defp subject_day(%Date{} = day), do: day

  defp subject_day(value) when is_binary(value) do
    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, day} -> day
      _invalid -> nil
    end
  end

  defp subject_day(_value), do: nil

  defp part(value) when is_binary(value) and value != "",
    do: String.slice(value, 0, @max_part_length)

  defp part(value) when is_integer(value), do: Integer.to_string(value)
  defp part(_value), do: nil

  defp field(payload, key) when is_map(payload),
    do: Map.get(payload, key) || Map.get(payload, safe_atom(key))

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
