defmodule Palee.BoxSite.Domain.DomainPolicy do
  @moduledoc """
  ADR-352 §5: the life of a custom host.

      pending_dns ──TXT + routing──▶ pending_tls ──HTTPS answers──▶ active
          │ 14 days                       ▲                          │
          ▼                               └──────── broken ◀─────────┘
        expired                                 (routing or TLS lost)

  Pure: callers bring the check facts and the time.
  """

  @statuses ~w(pending_dns pending_tls active broken expired)
  @challenge_prefix "_palee-challenge."
  @txt_prefix "palee-site-verification="
  @max_domains 2
  @expire_after_days 14
  @backoff_seconds [300, 900, 3_600, 21_600, 86_400]
  @active_recheck_seconds 86_400

  def statuses, do: @statuses
  def max_domains, do: @max_domains

  @doc "The TXT name a box adds to prove it controls `host`."
  def challenge_name(host), do: @challenge_prefix <> host

  @doc "The TXT value for a domain's token."
  def challenge_value(token), do: @txt_prefix <> token

  @doc "A fresh verification token (32 url-safe characters)."
  def new_token(random_bytes) when byte_size(random_bytes) >= 24,
    do: random_bytes |> Base.url_encode64(padding: false) |> binary_part(0, 32)

  @doc "The attributes of a newly added host."
  def new_domain(host, token, primary?, now) do
    %{
      host: host,
      verification_token: token,
      primary: primary?,
      status: "pending_dns",
      attempts: 0,
      next_check_at: now
    }
  end

  @doc """
  The DNS records the owner adds: the TXT proof, and a CNAME to
  `cname_target` or, for an apex host, A records.
  """
  def dns_records(%{host: host, verification_token: token}, apex?, cname_target, a_records) do
    routing =
      if apex? do
        Enum.map(a_records, &%{type: "A", name: host, value: &1})
      else
        [%{type: "CNAME", name: host, value: cname_target}]
      end

    [%{type: "TXT", name: challenge_name(host), value: challenge_value(token)} | routing]
  end

  @doc """
  Facts from DNS: whether the TXT proof is present and whether the host
  points at Palee (its CNAME is the target, or all its A records are ours).
  """
  def dns_facts(token, txt_values, cnames, a_values, cname_target, a_records) do
    target = normalize_name(cname_target)

    %{
      txt_ok: challenge_value(token) in Enum.map(txt_values, &String.trim/1),
      routing_ok:
        Enum.any?(cnames, &(normalize_name(&1) == target)) or
          (a_values != [] and a_records != [] and Enum.all?(a_values, &(&1 in a_records)))
    }
  end

  defp normalize_name(name), do: name |> String.downcase() |> String.trim_trailing(".")

  @doc """
  The changes after a check. `facts`: `txt_ok`, `routing_ok`, and `tls_ok`
  (nil when TLS was not probed because DNS failed).
  """
  def after_check(%{status: "pending_dns"} = domain, facts, now) do
    cond do
      facts.txt_ok and facts.routing_ok ->
        %{status: "pending_tls", verified_at: now, last_error: nil}
        |> Map.merge(advance(facts, now))
        |> settle(domain, now)

      expired?(domain, now) ->
        %{status: "expired", next_check_at: nil, last_error: dns_error(facts), checked_at: now}

      true ->
        retry(domain, dns_error(facts), now)
    end
  end

  def after_check(%{status: status} = domain, facts, now)
      when status in ["pending_tls", "active", "broken"] do
    cond do
      not facts.routing_ok and status == "pending_tls" ->
        domain |> retry("dns_not_pointing", now) |> Map.put(:status, "pending_dns")

      not facts.routing_ok ->
        broken(domain, "dns_not_pointing", now)

      facts.tls_ok ->
        %{
          status: "active",
          active_at: Map.get(domain, :active_at) || now,
          attempts: 0,
          last_error: nil,
          checked_at: now,
          next_check_at: DateTime.add(now, @active_recheck_seconds, :second)
        }

      status == "pending_tls" ->
        retry(domain, "tls_not_ready", now)

      true ->
        broken(domain, "tls_failed", now)
    end
  end

  def after_check(%{status: "expired"}, _facts, now),
    do: %{checked_at: now, next_check_at: nil}

  defp advance(%{tls_ok: true}, now),
    do: %{status: "active", active_at: now, attempts: 0, next_check_at: DateTime.add(now, @active_recheck_seconds, :second)}

  defp advance(_facts, now), do: %{attempts: 0, next_check_at: DateTime.add(now, hd(@backoff_seconds), :second)}

  defp settle(changes, _domain, now) do
    changes
    |> Map.put(:checked_at, now)
    |> then(fn
      %{status: "pending_tls"} = changes -> Map.put(changes, :last_error, "tls_not_ready")
      changes -> changes
    end)
  end

  defp broken(domain, error, now) do
    domain |> retry(error, now) |> Map.put(:status, "broken")
  end

  defp retry(domain, error, now) do
    attempts = (domain.attempts || 0) + 1

    %{
      attempts: attempts,
      last_error: error,
      checked_at: now,
      next_check_at: DateTime.add(now, backoff(attempts), :second)
    }
  end

  @doc "Seconds before the next check after `attempts` failed ones."
  def backoff(attempts) when attempts >= 1,
    do: Enum.at(@backoff_seconds, attempts - 1, List.last(@backoff_seconds))

  defp dns_error(%{txt_ok: false}), do: "dns_txt_missing"
  defp dns_error(_facts), do: "dns_not_pointing"

  defp expired?(domain, now) do
    added = Map.get(domain, :inserted_at) || now
    DateTime.diff(now, added, :second) > @expire_after_days * 86_400
  end

  @doc "Whether a host may get a certificate (Caddy's on-demand `ask`)."
  def tls_allowed?(status), do: status in ["pending_tls", "active"]

  @doc "Whether the site answers on this host (it serves while broken, to recover)."
  def serving?(status), do: status in ["pending_tls", "active", "broken"]
end
