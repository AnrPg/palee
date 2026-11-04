defmodule Palee.BoxSite.Domain.IngressPolicy do
  @moduledoc """
  ADR-398: when a custom host gets its Ingress (and so its certificate),
  how cluster calls are retried, and what the card says about the
  certificate.

      domain status      certificate_status
      pending_dns        none
      pending_tls ─────▶ pending ──Ingress applied──▶ issuing ──Ready──▶ active
      active / broken          │ cluster refused or         │ cert-manager
                               ▼ unreachable, 8 tries       ▼ gave up (for now)
                             failed                       failed

  The cluster's tenant policy refusing the host ("host not allowed": another
  tenant's or a system domain) is final: `failed` with `host_not_allowed`,
  the op is not retried, checks and the sweep leave it alone until the
  owner removes the domain and adds it again (ADR-398, 2026-11-03).

  A host has an Ingress while its domain is `pending_tls`, `active` or
  `broken`; it loses it when it falls back to `pending_dns`, expires or is
  removed. Pure: callers bring the facts and the time.
  """

  @wanted ~w(pending_tls active broken)
  @certificate_statuses ~w(none pending issuing active failed)
  @cluster_errors ~w(cluster_refused cluster_unreachable)
  @certificate_errors ~w(challenge_failed rate_limited issuer_not_ready issuance_failed)
  @host_not_allowed "host_not_allowed"
  @backoff_seconds [60, 300, 900, 3_600, 21_600]
  @max_attempts 8

  def certificate_statuses, do: @certificate_statuses
  def certificate_errors, do: @cluster_errors ++ @certificate_errors ++ [@host_not_allowed]
  def max_attempts, do: @max_attempts

  @doc "Whether a host in this domain status should have an Ingress."
  def wanted?(status), do: status in @wanted

  @doc "Whether the cluster refused the host for good (`host_not_allowed`)."
  def host_not_allowed?(domain),
    do:
      Map.get(domain, :certificate_status) == "failed" and
        Map.get(domain, :certificate_error) == @host_not_allowed

  @doc """
  The cluster call a status change needs: `:apply` when the host starts
  needing an Ingress, `:delete` when it stops, else `nil`.
  """
  def transition(before, after_status) do
    case {wanted?(before), wanted?(after_status)} do
      {false, true} -> :apply
      {true, false} -> :delete
      _same -> nil
    end
  end

  @doc """
  Whether a check should (re)queue the Ingress: the host needs one but has
  none yet (verified before Palee created Ingresses itself), or the cluster
  refused or could not be reached on every try.
  """
  def needs_apply?(%{status: status} = domain) do
    wanted?(status) and
      (domain.certificate_status == "none" or
         (domain.certificate_status == "failed" and domain.certificate_error in @cluster_errors))
  end

  @doc """
  Whether a check should read the certificate from the cluster: only while
  it is not active yet (issuing, or failed for a reason cert-manager retries).
  An active certificate is reread once a night by the sweep, so the 5-minute
  checks do not poll the cluster for every live host.
  """
  def read_certificate?(%{status: status} = domain) do
    wanted?(status) and
      (domain.certificate_status == "issuing" or
         (domain.certificate_status == "failed" and
            domain.certificate_error in @certificate_errors))
  end

  @doc "A new op for a host."
  def new_op(action, %{host: host} = domain, now) when action in [:apply, :delete] do
    %{
      domain_id: Map.get(domain, :id),
      host: host,
      action: Atom.to_string(action),
      status: "pending",
      attempts: 0,
      next_attempt_at: now,
      last_error: nil
    }
  end

  @doc "The domain's certificate fields once an op is queued."
  def queued(:apply), do: %{certificate_status: "pending", certificate_error: nil}
  def queued(:delete), do: %{certificate_status: "none", certificate_error: nil}

  @doc """
  The outcome of a cluster call. `attempts` already counts this one.
  Answers `{:done | op_changes, certificate_changes}`; certificate changes
  are empty for a delete.
  """
  def after_op(result, %{action: action, attempts: attempts}, now) do
    {op, certificate} = outcome(result, attempts, now)
    {op, if(action == "apply", do: certificate, else: %{})}
  end

  defp outcome(:ok, _attempts, _now),
    do: {:done, %{certificate_status: "issuing", certificate_error: nil}}

  defp outcome({:error, :host_not_allowed}, _attempts, _now),
    do:
      {%{status: "failed", last_error: @host_not_allowed, claimed_at: nil},
       %{certificate_status: "failed", certificate_error: @host_not_allowed}}

  defp outcome({:error, {kind, _reason}}, attempts, now) do
    error = if kind == :refused, do: "cluster_refused", else: "cluster_unreachable"

    if attempts >= @max_attempts do
      {%{status: "failed", last_error: error, claimed_at: nil},
       %{certificate_status: "failed", certificate_error: error}}
    else
      {%{
         status: "pending",
         last_error: error,
         claimed_at: nil,
         next_attempt_at: DateTime.add(now, backoff(attempts), :second)
       }, %{certificate_status: "pending", certificate_error: error}}
    end
  end

  defp outcome(_unexpected, attempts, now),
    do: outcome({:error, {:transient, :unexpected}}, attempts, now)

  @doc "Seconds before the next try after `attempts` failed ones."
  def backoff(attempts) when attempts >= 1,
    do: Enum.at(@backoff_seconds, attempts - 1, List.last(@backoff_seconds))

  @doc """
  The domain's certificate fields after reading the certificate:
  `{:ok, :issuing | :active | {:failed, reason}}`; a failed read changes
  nothing but the time.
  """
  def certificate_changes({:ok, :active}, now),
    do: %{certificate_status: "active", certificate_error: nil, certificate_checked_at: now}

  def certificate_changes({:ok, :issuing}, now),
    do: %{certificate_status: "issuing", certificate_error: nil, certificate_checked_at: now}

  def certificate_changes({:ok, {:failed, reason}}, now) do
    reason = to_string(reason)
    reason = if reason in @certificate_errors, do: reason, else: "issuance_failed"
    %{certificate_status: "failed", certificate_error: reason, certificate_checked_at: now}
  end

  def certificate_changes(_error, now), do: %{certificate_checked_at: now}
end
