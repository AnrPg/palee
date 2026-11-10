defmodule Palee.Application.MemberBenefits do
  @moduledoc """
  ADR-612: «Δώρο ή χάρη». Staff who take payments give a member something
  for free: a grace, free access, extra uses, a package or a forgiven debt
  (`Finance.Domain.MemberBenefits` holds the rules).

  Every grant and revocation is one row of an insert-only ledger, written in
  the same transaction as what it changes, with who did it (and their roles
  then), when, why, the request it came from and what it touched; the rows
  it touched name it back (usage entry metadata, credit entries,
  subscription). Each one is also logged and counted
  (`[:palee, :finance, :member_benefit, :granted | :revoked]`).

  Replays: the client sends `idempotency_key`; the same key answers the row
  already written (`replayed: true`) and changes nothing.
  """

  require Logger

  alias Palee.Application.{AssignFinanceMemberPackage, GrantUserAllowance, UpdateFinanceMember}
  alias Palee.{Finance, Organizations}
  alias Palee.Finance.Domain.MemberBenefits, as: Rules
  alias Palee.Finance.MemberBenefitStore

  @give [:take_payments]
  @read [:take_payments, :manage_billing, :manage_memberships]

  @doc "Every grant of a member with where it stands, newest first."
  def list(context, user_id) do
    with :ok <- authorize(context, @read) do
      Finance.with_tenant_context(context, fn ->
        case Finance.get_member_profile(context, user_id) do
          %{membership: %{id: membership_id}} ->
            {:ok, %{benefits: present(MemberBenefitStore.list(membership_id), today(context))}}

          _none ->
            {:ok, %{benefits: []}}
        end
      end)
    end
  end

  @doc """
  Gives a member a benefit. `params` (string keys): `kind`, `reason`,
  `idempotency_key` and what the kind needs (see `MemberBenefits`).
  `{:ok, %{benefit, replayed}}` or `{:error, reason}`.
  """
  def grant(context, user_id, params) when is_map(params) do
    today = today(context)

    with :ok <- authorize(context, @give),
         {:ok, key} <- idempotency_key(params),
         {:ok, grant} <- Rules.validate_grant(params, today) do
      Finance.with_tenant_context(context, fn ->
        case MemberBenefitStore.by_idempotency_key(key) do
          %{} = existing -> {:ok, %{benefit: presented(existing, today), replayed: true}}
          nil -> give(context, user_id, grant, key, today)
        end
      end)
    end
  end

  def grant(_context, _user_id, _params), do: {:error, :invalid_benefit}

  @doc """
  Revokes a grace, a free access or extra uses. `params`: `reason`
  (optional), `idempotency_key`.
  """
  def revoke(context, user_id, benefit_id, params) when is_map(params) do
    today = today(context)

    with :ok <- authorize(context, @give),
         {:ok, key} <- idempotency_key(params),
         {:ok, reason} <- Rules.reason(params["reason"]) do
      Finance.with_tenant_context(context, fn ->
        case MemberBenefitStore.by_idempotency_key(key) do
          %{} = existing -> {:ok, %{benefit: presented(existing, today), replayed: true}}
          nil -> take_back(context, user_id, benefit_id, reason, key, today)
        end
      end)
    end
  end

  def revoke(_context, _user_id, _benefit_id, _params), do: {:error, :invalid_benefit}

  # ── Giving ───────────────────────────────────────────────────────────────

  defp give(context, user_id, grant, key, today) do
    id = Ecto.UUID.generate()

    result =
      MemberBenefitStore.transaction(fn ->
        with {:ok, membership} <- membership(context, user_id, grant["kind"]),
             :ok <- still_a_member(membership),
             {:ok, effect} <- carry_out(context, user_id, membership, grant, id),
             {:ok, row} <-
               MemberBenefitStore.insert(
                 row(context, membership, grant, effect, id: id, key: key, action: "grant")
               ) do
          :ok = Finance.refresh_member_entitlement(context, membership.id)
          {:ok, row}
        end
      end)

    case result do
      {:ok, row} ->
        observe(:granted, context, row)
        {:ok, %{benefit: presented(row, today), replayed: false}}

      {:error, reason} = error ->
        Logger.warning(
          "member_benefit_refused kind=#{grant["kind"]} user_id=#{user_id} " <>
            "actor_id=#{context.user_id} reason=#{inspect(reason)}"
        )

        error
    end
  end

  # A grace, extra uses and a forgiven debt are for someone the box already
  # bills; free access and a package may be the first thing they get.
  defp membership(context, user_id, kind) when kind in ["free_access", "package"] do
    case Finance.get_member_profile(context, user_id) do
      %{membership: membership} ->
        {:ok, membership}

      nil ->
        UpdateFinanceMember.call(context, user_id, %{
          "status" => "active",
          "signup_source" => "admin_created"
        })
    end
  end

  defp membership(context, user_id, _kind) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: membership} -> {:ok, membership}
      nil -> {:error, :finance_profile_missing}
    end
  end

  # ADR-595: someone who left the box gets nothing until they join again.
  defp still_a_member(%{left_at: %DateTime{}}), do: {:error, :benefit_member_left}
  defp still_a_member(_membership), do: :ok

  defp carry_out(_context, _user_id, _membership, %{"kind" => kind}, _id)
       when kind in ["grace", "free_access"],
       do: {:ok, %{details: %{}, amount_cents: nil}}

  defp carry_out(context, user_id, _membership, %{"kind" => "extra_uses"} = grant, id) do
    case GrantUserAllowance.call(context, user_id, context.user_id, %{
           allowance: grant["allowance"],
           quantity: grant["quantity"],
           period: grant["period"],
           reason: grant["reason"] || "member_benefit",
           idempotency_key: "member-benefit:#{id}",
           metadata: %{"benefit_id" => id}
         }) do
      {:ok, %{entry: entry}} ->
        {:ok,
         %{
           details: %{
             "allowance" => grant["allowance"],
             "quantity" => grant["quantity"],
             "period" => grant["period"],
             "usage_entry_id" => entry.id,
             "subscription_id" => entry.membership_package_subscription_id
           },
           starts_on: entry.period_start,
           ends_on: entry.period_end,
           amount_cents: nil
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp carry_out(context, user_id, _membership, %{"kind" => "package"} = grant, _id) do
    with %{} = package <-
           Finance.get_package(context, grant["package_id"]) || {:error, :not_found},
         {:ok, subscription} <-
           AssignFinanceMemberPackage.call(
             context,
             user_id,
             %{"membership_package_id" => package.id},
             package_options(grant)
           ) do
      list_price = package.base_price_cents || 0
      price = if grant["pricing"] == "price", do: grant["price_cents"], else: list_price

      {:ok,
       %{
         details: %{
           "package_id" => package.id,
           "package_name" => package.name,
           "pricing" => grant["pricing"],
           "list_price_cents" => list_price,
           "price_cents" => price,
           "subscription_id" => subscription_id(subscription)
         },
         starts_on: Map.get(subscription, :starts_on),
         ends_on: Map.get(subscription, :ends_on),
         # What the box gives up: the period running now, or the difference
         # on every period from now.
         amount_cents:
           if(grant["pricing"] == "this_period_free",
             do: list_price,
             else: max(list_price - price, 0)
           )
       }}
    end
  end

  defp carry_out(context, _user_id, membership, %{"kind" => "debt_forgiven"} = grant, id) do
    grant["invoice_ids"]
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {invoice_id, index}, {:ok, done} ->
      case Finance.forgive_invoice(context, membership.id, invoice_id, %{
             # One request id per invoice, all derived from the benefit.
             "request_id" => derived_uuid(id, index),
             "created_by_id" => context.user_id,
             "description" => grant["reason"]
           }) do
        {:ok, forgiven} -> {:cont, {:ok, [forgiven | done]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, forgiven} ->
        forgiven = Enum.reverse(forgiven)

        {:ok,
         %{
           details: %{
             "invoices" =>
               Enum.map(forgiven, fn item ->
                 %{
                   "invoice_id" => item.invoice_id,
                   "invoice_number" => item.invoice_number,
                   "amount_cents" => item.amount_cents,
                   "grant_entry_id" => item.grant_entry_id,
                   "offset_entry_id" => item.offset_entry_id
                 }
               end)
           },
           amount_cents: forgiven |> Enum.map(& &1.amount_cents) |> Enum.sum()
         }}

      error ->
        error
    end
  end

  defp package_options(%{"pricing" => "this_period_free"}), do: [billing: :next_period]
  defp package_options(%{"pricing" => "price", "price_cents" => cents}), do: [price_cents: cents]

  defp subscription_id(%{id: id}), do: id
  defp subscription_id(_subscription), do: nil

  # ── Revoking ─────────────────────────────────────────────────────────────

  defp take_back(context, user_id, benefit_id, reason, key, today) do
    result =
      MemberBenefitStore.transaction(fn ->
        with {:ok, membership} <- membership(context, user_id, "grace"),
             %{} = grant <-
               MemberBenefitStore.lock_grant(membership.id, benefit_id) || {:error, :not_found},
             :ok <- revocable(grant, membership.id),
             :ok <- undo(context, user_id, grant, reason, key),
             {:ok, row} <-
               MemberBenefitStore.insert(%{
                 membership_id: membership.id,
                 user_id: membership.user_id,
                 action: "revoke",
                 kind: grant.kind,
                 benefit_id: grant.id,
                 reason: reason,
                 actor_id: context.user_id,
                 actor_roles: roles(context),
                 request_id: request_id(context),
                 idempotency_key: key,
                 details: %{}
               }) do
          :ok = Finance.refresh_member_entitlement(context, membership.id)
          {:ok, row}
        end
      end)

    case result do
      {:ok, row} ->
        observe(:revoked, context, row)
        {:ok, %{benefit: presented(row, today), replayed: false}}

      error ->
        error
    end
  end

  defp revocable(grant, membership_id) do
    cond do
      not Rules.revocable?(grant.kind) ->
        {:error, :benefit_not_revocable}

      Enum.any?(
        MemberBenefitStore.list(membership_id),
        &(&1.action == "revoke" and &1.benefit_id == grant.id)
      ) ->
        {:error, :benefit_already_revoked}

      true ->
        :ok
    end
  end

  defp undo(context, user_id, %{kind: "extra_uses", details: details}, reason, key) do
    case Finance.revoke_allowance_grant(
           context,
           user_id,
           context.user_id,
           details["usage_entry_id"],
           %{reason: reason || "member_benefit", idempotency_key: "member-benefit-revoke:#{key}"}
         ) do
      {:ok, _entry} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp undo(_context, _user_id, _grant, _reason, _key), do: :ok

  # ── The ledger row, its log line and its count ───────────────────────────

  defp row(context, membership, grant, effect, opts) do
    %{
      id: opts[:id],
      membership_id: membership.id,
      user_id: membership.user_id,
      action: opts[:action],
      kind: grant["kind"],
      starts_on: Map.get(effect, :starts_on) || grant["starts_on"],
      ends_on: Map.get(effect, :ends_on) || grant["ends_on"],
      amount_cents: effect.amount_cents,
      details: effect.details,
      reason: grant["reason"],
      actor_id: context.user_id,
      actor_roles: roles(context),
      request_id: request_id(context),
      idempotency_key: opts[:key]
    }
  end

  defp observe(event, context, row) do
    :telemetry.execute(
      [:palee, :finance, :member_benefit, event],
      %{count: 1, amount_cents: row.amount_cents || 0},
      %{kind: row.kind}
    )

    Logger.info(
      "member_benefit_#{event} benefit_id=#{row.benefit_id || row.id} kind=#{row.kind} " <>
        "organization_id=#{context.organization_id} membership_id=#{row.membership_id} " <>
        "user_id=#{row.user_id} actor_id=#{row.actor_id} " <>
        "actor_roles=#{Enum.join(row.actor_roles, ",")} request_id=#{row.request_id} " <>
        "starts_on=#{row.starts_on} ends_on=#{row.ends_on} amount_cents=#{row.amount_cents} " <>
        "reason_given=#{not is_nil(row.reason)}"
    )
  end

  # ── Presenting ───────────────────────────────────────────────────────────

  defp present(rows, today) do
    revocations = Enum.filter(rows, &(&1.action == "revoke"))

    rows
    |> Enum.filter(&(&1.action == "grant"))
    |> Enum.map(&present_one(&1, revocations, today))
  end

  # A grant or its revocation, shown as the grant with what happened to it.
  defp presented(row, today) do
    grant_id = row.benefit_id || row.id
    rows = MemberBenefitStore.list(row.membership_id)
    revocations = Enum.filter(rows, &(&1.action == "revoke"))

    rows
    |> Enum.find(&(&1.id == grant_id))
    |> present_one(revocations, today)
  end

  defp present_one(row, revocations, today) do
    revocation = Enum.find(revocations, &(&1.benefit_id == row.id))

    %{
      id: row.id,
      action: row.action,
      kind: row.kind,
      state: Rules.state(row, not is_nil(revocation), today),
      starts_on: row.starts_on,
      ends_on: row.ends_on,
      amount_cents: row.amount_cents,
      details: row.details,
      reason: row.reason,
      given_by_id: row.actor_id,
      given_by_roles: row.actor_roles,
      given_at: row.inserted_at,
      request_id: row.request_id,
      revocation:
        revocation &&
          %{
            reason: revocation.reason,
            by_id: revocation.actor_id,
            by_roles: revocation.actor_roles,
            at: revocation.inserted_at,
            request_id: revocation.request_id
          }
    }
  end

  # ── Small things ─────────────────────────────────────────────────────────

  defp authorize(context, capabilities) do
    if Enum.any?(capabilities, &Organizations.can?(context, &1)),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp idempotency_key(%{"idempotency_key" => key}) when is_binary(key) do
    key = String.trim(key)

    if byte_size(key) in 8..200,
      do: {:ok, "member-benefit:" <> key},
      else: {:error, :idempotency_key_required}
  end

  defp idempotency_key(_params), do: {:error, :idempotency_key_required}

  defp today(context), do: Organizations.local_today(context.organization_id)

  defp roles(context) do
    context
    |> Map.get(:roles, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp request_id(context), do: get_in(context, [Access.key(:request_metadata, %{}), :request_id])

  # A stable UUID per invoice of one forgiveness (the store wants UUIDs).
  defp derived_uuid(id, index) do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12),
      _rest::binary>> =
      :sha256 |> :crypto.hash("#{id}:#{index}") |> Base.encode16(case: :lower)

    Enum.join([a, b, c, d, e], "-")
  end
end
