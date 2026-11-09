defmodule Palee.Organizations.Domain.FollowerInvitePolicy do
  @moduledoc """
  ADR-580: a box invites the people who follow it to become box members.
  Pure rules; callers pass the facts.

    * **Who is listed** is worked out in the database (never box members,
      never people who turned «Δέχομαι προσκλήσεις από box» off, never
      people whose «Ζήτα να γίνεις μέλος» is open).
    * **Who may be invited** (`invitable?/3`): nobody who answered
      «Όχι, ευχαριστώ» to this box, and the same person again only
      `reinvite_after_days/0` days after the last invitation (ANR: 90).
    * **What an invitation holds** (`content/1`): an optional short message,
      an optional featured package and an optional trial offer. «Γίνε μέλος»
      always leads to the box page's own way in (ADR-552), never a dead end.
  """

  @statuses ~w(sent declined)
  @reinvite_after_days 90
  @message_max 500
  @batch_max 200
  @filters ~w(all trial former)

  def statuses, do: @statuses
  def reinvite_after_days, do: @reinvite_after_days
  def message_max, do: @message_max
  def batch_max, do: @batch_max
  def filters, do: @filters

  @doc "An invitation sent before this moment may be followed by another one."
  def reinvite_before(now), do: DateTime.add(now, -@reinvite_after_days * 86_400, :second)

  @doc """
  Whether a person may be invited now: `last` is their latest invitation
  from the box (`%{status, inserted_at}`, a declined one first), or nil.
  """
  def invitable?(nil, _now), do: true
  def invitable?(%{status: "declined"}, _now), do: false

  def invitable?(%{status: "sent", inserted_at: sent_at}, now),
    do: DateTime.diff(now, sent_at, :second) >= @reinvite_after_days * 86_400

  @doc "When the person may be invited again (nil: now, or never after a decline)."
  def next_invite_at(%{status: "sent", inserted_at: sent_at}),
    do: DateTime.add(sent_at, @reinvite_after_days * 86_400, :second)

  def next_invite_at(_last), do: nil

  @doc "The list filter: `all`, `trial` (did a trial) or `former` (former box members)."
  def filter(nil), do: {:ok, "all"}
  def filter(value) when value in @filters, do: {:ok, value}
  def filter(_other), do: {:error, :invalid_follower_filter}

  @doc """
  Checks what the staff send: up to `batch_max/0` distinct people, an
  optional message of at most `message_max/0` characters (blank is none),
  an optional package and an optional trial offer.
  """
  def content(params) do
    user_ids =
      params |> value(:user_ids) |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.uniq()

    message = params |> value(:message) |> blank_to_nil()

    cond do
      user_ids == [] ->
        {:error, :follower_invite_people_required}

      length(user_ids) > @batch_max ->
        {:error, :follower_invite_too_many}

      is_binary(message) and String.length(message) > @message_max ->
        {:error, :follower_invite_message_too_long}

      true ->
        {:ok,
         %{
           user_ids: user_ids,
           message: message,
           package_id: params |> value(:package_id) |> blank_to_nil(),
           offer_trial: value(params, :offer_trial) == true
         }}
    end
  end

  @doc "Whether the invitation still waits for the person's answer."
  def open?(%{status: "sent"}), do: true
  def open?(_invite), do: false

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil
end
