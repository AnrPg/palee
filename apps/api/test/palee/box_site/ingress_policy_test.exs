defmodule Palee.BoxSite.Domain.IngressPolicyTest do
  @moduledoc "ADR-398: when a host gets an Ingress, retries and the certificate's state."

  use ExUnit.Case, async: true

  alias Palee.BoxSite.Domain.IngressPolicy

  @now ~U[2026-11-03 10:00:00.000000Z]

  test "a host has an Ingress from DNS proof until it falls back, expires or goes" do
    assert IngressPolicy.transition("pending_dns", "pending_tls") == :apply
    assert IngressPolicy.transition("pending_dns", "active") == :apply
    assert IngressPolicy.transition("pending_tls", "pending_dns") == :delete
    assert IngressPolicy.transition("pending_tls", "active") == nil
    assert IngressPolicy.transition("active", "broken") == nil
    assert IngressPolicy.transition("pending_dns", "expired") == nil
  end

  test "a verified host without an Ingress, or refused by the cluster, is queued again" do
    domain = %{status: "active", certificate_status: "none", certificate_error: nil}
    assert IngressPolicy.needs_apply?(domain)

    refused = %{domain | certificate_status: "failed", certificate_error: "cluster_refused"}
    assert IngressPolicy.needs_apply?(refused)

    # cert-manager retries its own failures; Palee does not re-apply for them.
    challenge = %{domain | certificate_status: "failed", certificate_error: "challenge_failed"}
    refute IngressPolicy.needs_apply?(challenge)
    assert IngressPolicy.read_certificate?(challenge)

    refute IngressPolicy.needs_apply?(%{domain | status: "pending_dns"})
    refute IngressPolicy.needs_apply?(%{domain | certificate_status: "pending"})
    refute IngressPolicy.read_certificate?(%{domain | certificate_status: "pending"})
    assert IngressPolicy.read_certificate?(%{domain | certificate_status: "issuing"})
  end

  test "ops: done, retried with backoff, failed after the last try" do
    op = %{action: "apply", attempts: 1}

    assert IngressPolicy.after_op(:ok, op, @now) ==
             {:done, %{certificate_status: "issuing", certificate_error: nil}}

    {retry, certificate} = IngressPolicy.after_op({:error, {:transient, :unreachable}}, op, @now)
    assert retry.status == "pending"
    assert retry.next_attempt_at == DateTime.add(@now, 60, :second)

    assert certificate == %{
             certificate_status: "pending",
             certificate_error: "cluster_unreachable"
           }

    last = %{op | attempts: IngressPolicy.max_attempts()}
    {failed, certificate} = IngressPolicy.after_op({:error, {:refused, {:http, 403}}}, last, @now)
    assert failed.status == "failed"
    assert certificate == %{certificate_status: "failed", certificate_error: "cluster_refused"}

    # A delete never touches a domain's certificate fields.
    assert {_retry, %{}} =
             IngressPolicy.after_op(
               {:error, {:transient, :x}},
               %{action: "delete", attempts: 1},
               @now
             )

    assert IngressPolicy.backoff(1) == 60
    assert IngressPolicy.backoff(99) == 21_600
  end

  test "certificate changes" do
    assert %{certificate_status: "active", certificate_error: nil} =
             IngressPolicy.certificate_changes({:ok, :active}, @now)

    assert %{certificate_status: "failed", certificate_error: "rate_limited"} =
             IngressPolicy.certificate_changes({:ok, {:failed, :rate_limited}}, @now)

    assert %{certificate_error: "issuance_failed"} =
             IngressPolicy.certificate_changes({:ok, {:failed, :odd}}, @now)

    assert IngressPolicy.certificate_changes({:error, {:transient, :x}}, @now) ==
             %{certificate_checked_at: @now}
  end
end
