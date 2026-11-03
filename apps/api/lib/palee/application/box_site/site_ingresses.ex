defmodule Palee.Application.BoxSite.SiteIngresses do
  @moduledoc """
  ADR-398: Palee gives each verified custom host its own Ingress, and
  cert-manager issues the certificate.

    * `follow/4` queues the cluster call a host's new status needs (apply
      once DNS is proven, delete when it falls back, expires or is removed)
      and reads the certificate of a host that has an Ingress;
    * `run/2` works the box's outbox of cluster calls with retries
      (row claims, so overlapping runs are safe);
    * `sweep/0` (nightly) removes Ingresses of hosts no box has any more
      (a box that left, a lost op) and recreates missing ones (never one
      the cluster refused as `host_not_allowed`), and rereads active
      certificates; the 5-minute checks read only certificates still being
      issued.

  With no adapter configured (`config :palee, :box_site_ingress, nil`) all
  of this is off and ops use the list of ADR-352 §6.
  """

  require Logger

  alias Palee.BoxSite
  alias Palee.Workers.BoxSiteJob

  @batch 20

  @doc """
  After a host's status may have changed from `before_status`: queues the
  cluster call it needs, else refreshes its certificate state. Answers the
  domain as it now is.
  """
  def follow(context, before_status, domain, now) do
    # A host the cluster refused for good has no Ingress to make or delete;
    # the card keeps saying so until the owner removes the domain.
    if is_nil(BoxSite.site_ingress()) or BoxSite.host_not_allowed?(domain) do
      {:ok, domain}
    else
      case BoxSite.ingress_transition(before_status, domain.status) do
        nil ->
          if BoxSite.ingress_needs_apply?(domain),
            do: queue(context, :apply, domain, now),
            else: refresh_certificate(context, domain, now)

        action ->
          queue(context, action, domain, now)
      end
    end
  end

  @doc "A host was removed: its Ingress goes too."
  def removed(context, domain, now) do
    if BoxSite.site_ingress() &&
         (BoxSite.ingress_wanted?(domain.status) or domain.certificate_status != "none") do
      {:ok, _op} = BoxSite.queue_ingress_op(context, BoxSite.new_ingress_op(:delete, domain, now))
      schedule(context, now)
    end

    :ok
  end

  defp queue(context, action, domain, now) do
    {:ok, _op} = BoxSite.queue_ingress_op(context, BoxSite.new_ingress_op(action, domain, now))
    {:ok, domain} = BoxSite.update_domain(context, domain.id, BoxSite.ingress_queued(action))
    schedule(context, now)
    {:ok, BoxSite.get_domain(context, domain.id) || domain}
  end

  defp refresh_certificate(context, domain, now) do
    adapter = BoxSite.site_ingress()

    if BoxSite.read_certificate?(domain) do
      changes = BoxSite.certificate_changes(safe(fn -> adapter.certificate(domain.host) end), now)
      BoxSite.update_domain(context, domain.id, changes)
    else
      {:ok, domain}
    end
  end

  # Background jobs pick it up at once; without them (tests, tasks) inline.
  defp schedule(%{organization_id: organization_id} = context, now) do
    if Application.get_env(:palee, :start_oban, true) do
      %{"organization_id" => organization_id} |> BoxSiteJob.new() |> Oban.insert()
    else
      run(context, now)
    end
  end

  @doc "One pass over the box's cluster calls; answers how many succeeded."
  def run(context, now) do
    case BoxSite.site_ingress() do
      nil ->
        0

      adapter ->
        context
        |> BoxSite.claim_ingress_ops(now, @batch)
        |> Enum.count(&perform(context, adapter, &1, now))
    end
  end

  defp perform(context, adapter, op, now) do
    result =
      case op.action do
        "apply" -> safe(fn -> adapter.apply_site(op.host) end)
        "delete" -> safe(fn -> adapter.remove_site(op.host) end)
      end

    {op_changes, certificate} = BoxSite.after_ingress_op(result, op, now)
    :ok = BoxSite.finish_ingress_op(context, op.id, op_changes)

    if certificate != %{} and op.domain_id do
      # The domain may be gone meanwhile; then there is nothing to show.
      BoxSite.update_domain(context, op.domain_id, certificate)
    end

    result == :ok
  end

  @doc """
  Nightly: Ingresses whose host no box has any more are deleted, hosts that
  should have one but do not get it again, and active certificates are
  reread (a renewal that failed for good shows on the card). The cluster is
  read before the database, so a host verified meanwhile is never taken for
  an orphan.
  """
  def sweep do
    with adapter when not is_nil(adapter) <- BoxSite.site_ingress(),
         {:ok, managed} <- safe(fn -> adapter.managed_hosts() end) do
      hosts = BoxSite.ingress_hosts()
      wanted = MapSet.new(hosts, & &1.host)
      managed = MapSet.new(managed)

      removed =
        managed
        |> MapSet.difference(wanted)
        |> Enum.count(&(safe(fn -> adapter.remove_site(&1) end) == :ok))

      restored =
        wanted
        |> MapSet.difference(managed)
        |> Enum.count(&(safe(fn -> adapter.apply_site(&1) end) == :ok))

      certificates =
        hosts
        |> Enum.filter(&(&1.certificate_status == "active" and MapSet.member?(managed, &1.host)))
        |> Enum.count(&reread_certificate(adapter, &1))

      {:ok, %{removed: removed, restored: restored, certificates: certificates}}
    else
      nil -> {:ok, %{removed: 0, restored: 0, certificates: 0}}
      {:error, _reason} = error -> error
    end
  end

  # True when the certificate is no longer active (the change is saved).
  defp reread_certificate(adapter, %{organization_id: organization_id, id: id, host: host}) do
    case safe(fn -> adapter.certificate(host) end) do
      {:ok, :active} ->
        false

      {:ok, _other} = result ->
        context = %{organization_id: organization_id}

        BoxSite.update_domain(
          context,
          id,
          BoxSite.certificate_changes(result, BoxSite.clock().now())
        )

        true

      _error ->
        false
    end
  end

  defp safe(fun) do
    fun.()
  rescue
    error ->
      Logger.error("site ingress call failed: #{Exception.message(error)}")
      {:error, {:transient, :crashed}}
  end
end
