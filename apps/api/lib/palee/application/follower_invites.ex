defmodule Palee.Application.FollowerInvites do
  @moduledoc """
  ADR-580: a box invites the people who follow it to become box members,
  one person or many at once (ANR 2026-11-09, «C»).

    * **Staff** (`summary/1`, `list/2`, `send/2`): the Χρήστες card counts
      the followers who are not box members; the list shows them with
      «Πρώην μέλος», «Δοκιμαστικό», «Εστάλη» and «Δεν θέλει προσκλήσεις»;
      one send takes up to 200 people with an optional short message, an
      optional featured package (one the box lists to everyone) and an
      optional trial offer (only while the box takes trials).
    * **Each invitation** is a `follower_invited` notification (bell and
      push) and the same words as a message from the box in the person's
      Μηνύματα › Box. The message itself stays quiet, so the person hears
      once.
    * **The person** (`mine/2`, `decline/2`) sees the invitation on the box
      page: «Γίνε μέλος» is the page's own way in (ADR-552); «Όχι,
      ευχαριστώ» stops further invitations from that box.

  Rules live in `Organizations.Domain.FollowerInvitePolicy`; who is listed
  is worked out by the store (never box members, never people who turned
  «Δέχομαι προσκλήσεις από box» off, never open join requests).
  """

  require Logger

  alias Palee.Application.{GetOrCreateMessagingThread, PublicBox, SendMessage}
  alias Palee.Application.Payments.PackageAudience
  alias Palee.{Community, Identity, Localization, Messaging, Notifications, Organizations, Trials}
  alias Palee.Organizations.Domain.FollowerInvitePolicy
  alias Palee.Organizations.FollowerInviteStore

  @page 50

  # ── Staff ───────────────────────────────────────────────────────────────

  @doc "What the Χρήστες card needs: `%{listed, invitable, trial, former}`."
  def summary(context, now \\ DateTime.utc_now()) do
    with :ok <- Organizations.authorize_capability(context, :manage_memberships) do
      {:ok,
       FollowerInviteStore.with_scope(scope_of(context), fn -> FollowerInviteStore.counts(now) end)}
    end
  end

  @doc """
  One page of followers who are not box members (`filter`: all, trial,
  former; `cursor` from the previous page), with what a send may hold.
  """
  def list(context, params, now \\ DateTime.utc_now()) do
    with :ok <- Organizations.authorize_capability(context, :manage_memberships),
         {:ok, filter} <- FollowerInvitePolicy.filter(value(params, :filter)),
         {:ok, before} <- Community.decode_feed_cursor(value(params, :cursor)) do
      {rows, counts} =
        FollowerInviteStore.with_scope(scope_of(context), fn ->
          {FollowerInviteStore.list_followers(filter, @page + 1, before, now),
           FollowerInviteStore.counts(now)}
        end)

      {page, rest} = Enum.split(rows, @page)
      people = page |> Enum.map(& &1.user_id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

      {:ok,
       %{
         followers:
           page
           |> Enum.filter(&Map.has_key?(people, &1.user_id))
           |> Enum.map(&present_follower(&1, people[&1.user_id])),
         next_cursor: next_cursor(page, rest),
         counts: counts,
         offer: offer(context)
       }}
    end
  end

  @doc """
  Invites the people in `params.user_ids`. Only listed followers who may be
  invited now are; the others come back in `skipped` with the reason.
  """
  def send(context, params, now \\ DateTime.utc_now()) do
    with :ok <- Organizations.authorize_capability(context, :manage_memberships),
         {:ok, content} <- FollowerInvitePolicy.content(params),
         :ok <- check_package(context, content.package_id),
         :ok <- check_trial(context, content.offer_trial) do
      scope = scope_of(context)

      followers =
        FollowerInviteStore.with_scope(scope, fn ->
          FollowerInviteStore.followers_among(content.user_ids, now)
        end)

      {ready, skipped} = split_invitable(content.user_ids, followers)

      with {:ok, invites} <- create(scope, ready, content, context.user_id, now) do
        box = box_of(context)
        actor = Identity.find_by_id(context.user_id)
        Enum.each(invites, &deliver(context, actor, box, &1))

        {:ok, %{sent: length(invites), skipped: skipped}}
      end
    end
  end

  defp split_invitable(user_ids, followers) do
    Enum.reduce(user_ids, {[], []}, fn user_id, {ready, skipped} ->
      case followers do
        %{^user_id => %{invitable: true}} ->
          {[user_id | ready], skipped}

        %{^user_id => %{invite_status: "declined"}} ->
          {ready, [%{user_id: user_id, reason: "declined"} | skipped]}

        %{^user_id => _recent} ->
          {ready, [%{user_id: user_id, reason: "recently_invited"} | skipped]}

        _not_listed ->
          {ready, [%{user_id: user_id, reason: "not_a_follower"} | skipped]}
      end
    end)
    |> then(fn {ready, skipped} -> {Enum.reverse(ready), Enum.reverse(skipped)} end)
  end

  defp create(_scope, [], _content, _actor_id, _now), do: {:ok, []}

  defp create(scope, user_ids, content, actor_id, now) do
    FollowerInviteStore.with_scope(scope, fn ->
      FollowerInviteStore.create_many(
        user_ids,
        Map.put(content, :invited_by_id, actor_id),
        now
      )
    end)
  end

  # The package must be one the box lists to everyone (ADR-553: what a
  # follower would see on the page without being a member).
  defp check_package(_context, nil), do: :ok

  defp check_package(context, package_id) do
    if Enum.any?(listed_packages(context), &(&1.id == package_id)),
      do: :ok,
      else: {:error, :package_not_for_sale}
  end

  defp check_trial(_context, false), do: :ok

  defp check_trial(context, true) do
    if trials_open?(context), do: :ok, else: {:error, :trials_closed}
  end

  @doc "What a send may hold: the packages listed to everyone and whether trials are open."
  def offer(context) do
    %{
      packages:
        Enum.map(listed_packages(context), fn package ->
          %{
            id: package.id,
            name: package.name,
            price_cents: package.base_price_cents,
            currency: package.currency,
            billing_period: package.billing_period
          }
        end),
      trial_available: trials_open?(context)
    }
  end

  defp listed_packages(context),
    do: PackageAudience.view(%{organization_id: context.organization_id}, nil).packages

  defp trials_open?(context),
    do: Trials.policy(%{organization_id: context.organization_id}).enabled == true

  # ── Delivery ────────────────────────────────────────────────────────────

  # The bell and push first (they carry «Γίνε μέλος»); then the same words
  # in the person's Μηνύματα › Box, quietly. A failed message never undoes
  # a sent invitation: the person still has the notification.
  defp deliver(context, actor, box, invite) do
    Notifications.dispatch_event(:follower_invited, %{
      organization_id: context.organization_id,
      user_id: invite.user_id,
      follower_invite_id: invite.id,
      box_name: box && box.name,
      box_slug: box && box.slug,
      message: invite.message
    })

    with %{} <- actor,
         {:ok, thread} <-
           GetOrCreateMessagingThread.for_invited_follower(context, actor, invite.user_id),
         {:ok, _message} <-
           Messaging.with_tenant_context(context, fn ->
             SendMessage.call(
               actor,
               %{
                 thread_id: thread.id,
                 sender_id: actor.id,
                 body: thread_text(invite, box),
                 client_operation_id: invite.id
               },
               notify: false
             )
           end) do
      :ok
    else
      other ->
        Logger.warning("follower invite #{invite.id}: no box message (#{inspect(other)})")
        :ok
    end
  end

  # The box's own words, else a plain line in the box's voice. The page link
  # always follows, so the message leads to «Γίνε μέλος» as well.
  defp thread_text(invite, box) do
    link = box && "/b/#{box.slug}"

    [invite.message || default_text(invite.user_id, box), link]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp default_text(user_id, box) do
    locale =
      case Identity.find_by_id(user_id) do
        %{preferred_locale: locale} when is_binary(locale) -> locale
        _none -> "en"
      end

    Localization.translate(
      locale,
      "%{box} invites you to become a member.",
      %{box: (box && box.name) || ""},
      "notifications"
    )
  end

  # ── The person ──────────────────────────────────────────────────────────

  @doc """
  The person's open invitation from the box, or nil: the box's message,
  the featured package while they still see it, and whether a trial is
  offered.
  """
  def mine(%{id: user_id}, slug) do
    with {:ok, box, scope} <- PublicBox.resolve(slug) do
      invite =
        FollowerInviteStore.with_scope(person_scope(scope, user_id), fn ->
          FollowerInviteStore.latest_for(user_id)
        end)

      {:ok, present_mine(invite, box, scope, user_id)}
    end
  end

  @doc "«Όχι, ευχαριστώ»: no more invitations from this box."
  def decline(%{id: user_id}, slug, now \\ DateTime.utc_now()) do
    with {:ok, box, scope} <- PublicBox.resolve(slug),
         {:ok, declined} <-
           FollowerInviteStore.with_scope(person_scope(scope, user_id), fn ->
             FollowerInviteStore.decline(user_id, now)
           end),
         %{} <- declined || {:error, :not_found} do
      {:ok, present_mine(declined, box, scope, user_id)}
    end
  end

  defp present_mine(nil, _box, _scope, _user_id), do: nil

  defp present_mine(invite, box, scope, user_id) do
    if FollowerInvitePolicy.open?(invite) and
         Organizations.membership_standing(scope.organization_id, user_id) != :member do
      %{
        id: invite.id,
        status: invite.status,
        sent_at: invite.inserted_at,
        message: invite.message,
        offer_trial: invite.offer_trial,
        package: featured(scope, invite.package_id, user_id),
        box: %{slug: box.slug, name: box.name}
      }
    else
      nil
    end
  end

  defp featured(_scope, nil, _user_id), do: nil

  defp featured(scope, package_id, user_id) do
    scope
    |> PackageAudience.view(user_id)
    |> Map.get(:packages, [])
    |> Enum.find(&(&1.id == package_id))
    |> case do
      nil ->
        nil

      package ->
        %{
          id: package.id,
          name: package.name,
          price_cents: package.base_price_cents,
          currency: package.currency,
          billing_period: package.billing_period
        }
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp present_follower(row, person) do
    last = row.invite_status && %{status: row.invite_status, inserted_at: row.invited_at}

    %{
      person: %{
        id: person.id,
        nickname: person.nickname,
        handle: Map.get(person, :handle),
        avatar_url: Map.get(person, :avatar_url)
      },
      followed_at: row.followed_at,
      former_member: row.former_member,
      had_trial: row.had_trial,
      invite:
        last &&
          %{
            status: last.status,
            sent_at: last.inserted_at,
            next_invite_at: FollowerInvitePolicy.next_invite_at(last)
          },
      invitable: row.invitable
    }
  end

  defp next_cursor(page, rest) do
    case {page, rest} do
      {[_ | _], [_ | _]} ->
        last = List.last(page)
        Community.encode_feed_cursor(%{inserted_at: last.followed_at, id: last.user_id})

      _end ->
        nil
    end
  end

  defp box_of(context),
    do: context.organization_id |> List.wrap() |> PublicBox.boxes() |> List.first()

  defp person_scope(scope, user_id),
    do: %{organization_id: scope.organization_id, user_id: user_id}

  defp scope_of(context),
    do: %{organization_id: context.organization_id, user_id: context.user_id}

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
