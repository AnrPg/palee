defmodule Palee.Application.JoinBox do
  @moduledoc """
  ADR-552: becoming a box member when the member join link is not the way.

    * **Buying** (`for_package/3`). Starting to buy, or to ask for, a package
      the box lists to everyone makes the person a box member, whatever the
      join link says: the box already said yes to whoever buys it. The
      existing member checkout and «Το θέλω» then run as for any member.
    * **Asking** (`ask/2`, `mine/2`, `cancel/2`). «Ζήτα να γίνεις μέλος»:
      one open request per person and box, which the staff accept or
      decline (`list/1`, `decide/3`). Accepting admits the person (a former
      member too) and tells them; declining tells them as well.

  The rules live in `Organizations.Domain.JoinRequestPolicy`.
  """

  alias Palee.Application.{JoinOrganizationByLink, PublicBox}
  alias Palee.Application.Payments.OnlineSales
  alias Palee.{Identity, Notifications, Organizations}
  alias Palee.Organizations.Domain.JoinRequestPolicy
  alias Palee.Organizations.JoinRequestStore

  # ── Buying ──────────────────────────────────────────────────────────────

  @doc "Admits the person to buy `package_id`, which the box must list to everyone."
  def for_package(%{id: user_id} = user, slug, package_id) do
    with {:ok, _box, scope} <- PublicBox.resolve(slug),
         :ok <- listed(scope, package_id),
         {:ok, result} <- Organizations.admit_member(scope.organization_id, user_id, :purchase),
         {:ok, _user} <- JoinOrganizationByLink.align_role(user, result) do
      {:ok, result}
    end
  end

  defp listed(scope, package_id) do
    if Enum.any?(OnlineSales.listed_packages(scope), &(&1.id == package_id)),
      do: :ok,
      else: {:error, :package_not_for_sale}
  end

  # ── Asking ──────────────────────────────────────────────────────────────

  @doc "«Ζήτα να γίνεις μέλος»; asking again returns the open request."
  def ask(%{id: user_id} = user, slug) do
    with {:ok, box, scope} <- PublicBox.resolve(slug),
         :ok <- JoinRequestPolicy.can_ask?(standing(scope, user_id)),
         context = person_scope(scope, user_id),
         {:ok, request, how} <-
           JoinRequestStore.with_scope(context, fn -> JoinRequestStore.ask(user_id) end) do
      if how == :created, do: notify_staff(scope, request, user, box)
      {:ok, present_mine(request, box)}
    end
  end

  @doc "The person's latest request at the box, or nil."
  def mine(%{id: user_id}, slug) do
    with {:ok, box, scope} <- PublicBox.resolve(slug) do
      request =
        JoinRequestStore.with_scope(person_scope(scope, user_id), fn ->
          JoinRequestStore.latest_for(user_id)
        end)

      {:ok, request && present_mine(request, box)}
    end
  end

  @doc "Withdraws the person's open request."
  def cancel(%{id: user_id}, slug) do
    with {:ok, box, scope} <- PublicBox.resolve(slug) do
      JoinRequestStore.with_scope(person_scope(scope, user_id), fn ->
        case JoinRequestStore.latest_for(user_id) do
          %{status: "requested", id: id} ->
            with {:ok, closed} <-
                   JoinRequestStore.close(id, %{
                     status: "cancelled",
                     decided_at: DateTime.utc_now()
                   }) do
              {:ok, present_mine(closed, box)}
            end

          _none ->
            {:error, :not_found}
        end
      end)
    end
  end

  # ── Staff ───────────────────────────────────────────────────────────────

  @doc "Open requests of the box in `context`, oldest first, with who asks."
  def list(context) do
    requests = JoinRequestStore.with_scope(scope_of(context), &JoinRequestStore.list_open/0)
    people = requests |> Enum.map(& &1.user_id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
    Enum.map(requests, &present_staff(&1, people[&1.user_id]))
  end

  @doc "Accepts (`\"accept\"`) or declines (`\"decline\"`) an open request."
  def decide(context, request_id, action) do
    now = DateTime.utc_now()

    with {:ok, status} <- JoinRequestPolicy.decision(action),
         %{} = request <-
           JoinRequestStore.with_scope(scope_of(context), fn ->
             JoinRequestStore.get(request_id)
           end) ||
             {:error, :not_found},
         true <- JoinRequestPolicy.open?(request.status) || {:error, :join_request_closed},
         :ok <- admit_if_accepted(status, context, request, now),
         {:ok, closed} <-
           JoinRequestStore.with_scope(scope_of(context), fn ->
             JoinRequestStore.close(request.id, %{
               status: status,
               decided_at: now,
               decided_by_id: context.user_id
             })
           end) do
      notify_person(context, closed)
      {:ok, present_staff(closed, Identity.find_by_id(closed.user_id))}
    end
  end

  defp admit_if_accepted("accepted", context, request, now) do
    with {:ok, result} <-
           Organizations.admit_member(
             context.organization_id,
             request.user_id,
             :accepted_request,
             now
           ),
         %{} = person <- Identity.find_by_id(request.user_id) || {:error, :not_found},
         {:ok, _user} <- JoinOrganizationByLink.align_role(person, result) do
      :ok
    end
  end

  defp admit_if_accepted(_declined, _context, _request, _now), do: :ok

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp standing(scope, user_id),
    do: Organizations.membership_standing(scope.organization_id, user_id)

  defp person_scope(scope, user_id),
    do: %{organization_id: scope.organization_id, user_id: user_id}

  defp scope_of(context),
    do: %{organization_id: context.organization_id, user_id: context.user_id}

  defp notify_staff(scope, request, user, box) do
    Notifications.dispatch_event(:join_requested, %{
      organization_id: scope.organization_id,
      join_request_id: request.id,
      person_nickname: user.nickname,
      box_name: box.name
    })
  end

  defp notify_person(context, request) do
    box = context.organization_id |> List.wrap() |> PublicBox.boxes() |> List.first()

    Notifications.dispatch_event(
      if(request.status == "accepted", do: :join_request_accepted, else: :join_request_declined),
      %{
        organization_id: context.organization_id,
        user_id: request.user_id,
        join_request_id: request.id,
        box_name: box && box.name,
        box_slug: box && box.slug
      }
    )
  end

  defp present_mine(request, box) do
    %{
      id: request.id,
      status: request.status,
      requested_at: request.inserted_at,
      decided_at: request.decided_at,
      box: %{slug: box.slug, name: box.name}
    }
  end

  defp present_staff(request, person) do
    %{
      id: request.id,
      status: request.status,
      requested_at: request.inserted_at,
      decided_at: request.decided_at,
      person:
        person &&
          %{
            id: person.id,
            nickname: person.nickname,
            handle: Map.get(person, :handle),
            avatar_url: Map.get(person, :avatar_url)
          }
    }
  end
end
