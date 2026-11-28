defmodule Palee.Application.ChangeClientRoles do
  @moduledoc """
  ADR-812: staff change the box roles of one or many clients from the
  finance ledger (Οικονομικά › Μέλη box), and see first what the change does.

  One request names the people and the roles to add and to remove; each
  person's new role set is their current one with those applied, so a bulk
  change never wipes roles it does not name. Every person goes through
  `ChangeMembershipRoles.set_roles/3`, the path the profile uses, with the
  same rights (who may grant which role, branch managers, the last owner, the
  plan's seats); the request itself needs the right to change roles
  (`grant_staff_roles`), also for a preview. One person failing never undoes the others.

  A ledger change keeps the person a client of the box: their new roles must
  hold a buyer role (Μέλος box, Αθλητής or Επισκέπτης), else that person is
  refused with `client_role_required`. Leaving the box is its own action.

  With `dry_run?` (the preview route) nothing changes and each result carries the impact:
    * `future_bookings`: bookings that would be cancelled (only when the
      person stops being a member or athlete of the box; dropping «Μέλος box»
      while still an athlete keeps them);
    * `kept_package`: the running subscription package that stays until its
      last day while the person no longer books as a member or athlete.
  """

  alias Palee.Application.ChangeMembershipRoles
  alias Palee.{Finance, Organizations, Scheduling}
  alias Palee.Organizations.Commands.SetMembershipRole
  alias Palee.Organizations.Domain.{MembershipPolicy, TenantAuthorization}

  @max_users 50

  @doc "The most people one request may change."
  def max_users, do: @max_users

  def call(context, params, dry_run? \\ false)

  def call(%{organization_id: organization_id} = context, params, dry_run?)
      when is_binary(organization_id) and is_map(params) and is_boolean(dry_run?) do
    with :ok <- TenantAuthorization.authorize_capability(context, :grant_staff_roles),
         {:ok, ids} <- user_ids(param(params, :user_ids)),
         {:ok, add} <- roles(param(params, :add)),
         {:ok, remove} <- roles(param(params, :remove)),
         :ok <- not_both(add, remove) do
      summaries = if dry_run?, do: package_summaries(context, ids), else: %{}

      results =
        Enum.map(ids, fn user_id ->
          change_one(context, user_id, add, remove, dry_run?, Map.get(summaries, user_id))
        end)

      {:ok, %{results: results}}
    end
  end

  def call(_context, _params, _dry_run?), do: {:error, :organization_context_required}

  defp change_one(context, user_id, add, remove, dry_run?, summary) do
    current = Organizations.member_roles(context.organization_id, user_id)
    next = next_roles(current, add, remove)

    cond do
      current == [] ->
        refused(user_id, current, :not_found)

      next == current ->
        result(user_id, "unchanged", current)

      not MembershipPolicy.buyer?(next) ->
        refused(user_id, current, :client_role_required)

      dry_run? ->
        user_id
        |> result("preview", next)
        |> Map.put(:impact, impact(context, user_id, current, next, summary))

      true ->
        case ChangeMembershipRoles.set_roles(context, user_id, next) do
          {:ok, membership} -> result(user_id, "changed", membership.roles)
          {:error, reason} -> refused(user_id, current, reason)
          _other -> refused(user_id, current, :unexpected_server_error)
        end
    end
  end

  @doc "A role set with `add` and `remove` applied, in the canonical role order."
  def next_roles(current, add, remove) do
    held = Enum.uniq((List.wrap(current) -- List.wrap(remove)) ++ List.wrap(add))
    Enum.filter(MembershipPolicy.roles(), &(&1 in held))
  end

  defp impact(context, user_id, current, next, summary) do
    stops_booking? = MembershipPolicy.client?(current) and not MembershipPolicy.client?(next)

    %{
      future_bookings:
        if(SetMembershipRole.cancels_bookings?(current, next),
          do: Scheduling.count_active_future_bookings_for_user(context, user_id),
          else: 0
        ),
      kept_package: if(stops_booking?, do: running_package(summary), else: nil)
    }
  end

  defp running_package(%{active_package_subscription: %{} = subscription}) do
    if subscription[:status] in ["active", "paused"] do
      %{name: subscription[:package_name], ends_on: subscription[:ends_on]}
    end
  end

  defp running_package(_summary), do: nil

  defp package_summaries(context, ids),
    do: Finance.search_member_summaries(context, %{user_ids: ids, limit: length(ids)})

  defp result(user_id, status, roles),
    do: %{user_id: user_id, status: status, roles: Enum.map(roles, &to_string/1)}

  defp refused(user_id, roles, reason) do
    user_id
    |> result("refused", roles)
    |> Map.put(:code, code(reason))
  end

  defp code(reason) when is_atom(reason), do: to_string(reason)
  defp code({reason, _details}) when is_atom(reason), do: to_string(reason)
  defp code(%Ecto.Changeset{}), do: "validation_failed"
  defp code(_reason), do: "unexpected_server_error"

  defp user_ids(ids) when is_list(ids) do
    case ids |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.uniq() do
      [] -> {:error, :invalid_user_ids}
      ids when length(ids) > @max_users -> {:error, :too_many_users}
      ids -> {:ok, ids}
    end
  end

  defp user_ids(_ids), do: {:error, :invalid_user_ids}

  defp roles(nil), do: {:ok, []}
  defp roles([]), do: {:ok, []}

  defp roles(roles) when is_list(roles) do
    case MembershipPolicy.normalize_roles(roles) do
      {:ok, roles} -> {:ok, roles}
      {:error, _reason} -> {:error, :invalid_role}
    end
  end

  defp roles(_roles), do: {:error, :invalid_role}

  defp not_both(add, remove) do
    cond do
      add == [] and remove == [] -> {:error, :roles_required}
      Enum.any?(add, &(&1 in remove)) -> {:error, :invalid_role}
      true -> :ok
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
