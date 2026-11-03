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
  @unknown_recheck_seconds 300

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
  `cname_target`. An apex host cannot have a CNAME, so its record is an
  `ALIAS` to the same target: CNAME flattening, ALIAS or ANAME, whatever the
  provider calls it. Never fixed A records: the cluster's addresses change
  (ADR-398, 2026-11-03).
  """
  def dns_records(%{host: host, verification_token: token}, apex?, cname_target) do
    routing = %{type: if(apex?, do: "ALIAS", else: "CNAME"), name: host, value: cname_target}
    [%{type: "TXT", name: challenge_name(host), value: challenge_value(token)}, routing]
  end

  @doc """
  Facts from DNS: whether the TXT proof is present (`txt_ok`) and whether the
  host points at Palee (`routing_ok`). Each is `true`, `false` or `:unknown`
  (the resolver could not tell; the check then keeps the host's state).

  `lookups` holds `{:ok, values} | {:error, reason}` for `:txt` (the
  challenge name), `:cname_chain` (the names the host's CNAMEs lead to),
  `:a`/`:aaaa` (the host's addresses) and `:target_a`/`:target_aaaa` (the
  target's addresses right now).

  The host points here when its CNAME chain reaches the target, or when it
  has at least one address and every A and AAAA it has is among the target's
  current ones (CNAME flattening at the apex). An address that is not the
  target's would send some visitors, and Let's Encrypt, elsewhere.
  """
  def dns_facts(token, lookups, cname_target) do
    %{
      txt_ok: txt_ok(token, Map.fetch!(lookups, :txt)),
      routing_ok:
        either(
          cname_ok(Map.fetch!(lookups, :cname_chain), cname_target),
          addresses_ok(lookups)
        )
    }
  end

  defp txt_ok(token, {:ok, values}),
    do: challenge_value(token) in Enum.map(values, &String.trim/1)

  defp txt_ok(_token, {:error, _reason}), do: :unknown

  defp cname_ok({:ok, names}, target) do
    target = normalize_name(target)
    Enum.any?(names, &(normalize_name(&1) == target))
  end

  defp cname_ok({:error, _reason}, _target), do: :unknown

  defp addresses_ok(%{
         a: {:ok, a},
         aaaa: {:ok, aaaa},
         target_a: {:ok, ta},
         target_aaaa: {:ok, taaaa}
       }) do
    {a, aaaa, ta, taaaa} = {addresses(a), addresses(aaaa), addresses(ta), addresses(taaaa)}

    cond do
      # Palee's own name not resolving is Palee's problem, not the box's.
      ta == [] and taaaa == [] -> :unknown
      a == [] and aaaa == [] -> false
      true -> Enum.all?(a, &(&1 in ta)) and Enum.all?(aaaa, &(&1 in taaaa))
    end
  end

  defp addresses_ok(_lookups), do: :unknown

  defp addresses(values),
    do: values |> Enum.map(&(&1 |> String.trim() |> String.downcase())) |> Enum.uniq()

  defp either(true, _other), do: true
  defp either(_one, true), do: true
  defp either(:unknown, _other), do: :unknown
  defp either(_one, :unknown), do: :unknown
  defp either(false, false), do: false

  @doc "A DNS name without case or trailing dot."
  def normalize_name(name),
    do: name |> String.trim() |> String.downcase() |> String.trim_trailing(".")

  @doc """
  The changes after a check. `facts`: `txt_ok`, `routing_ok` (each `true`,
  `false` or `:unknown`), and `tls_ok` (false when TLS was not probed).

  A fact the resolver could not tell never moves a host: it keeps its state
  and is looked at again soon, so a resolver hiccup does not delete and
  recreate its Ingress (ADR-398, 2026-11-03).
  """
  def after_check(%{status: "pending_dns"} = domain, facts, now) do
    cond do
      facts.txt_ok == true and facts.routing_ok == true ->
        %{status: "pending_tls", verified_at: now, last_error: nil}
        |> Map.merge(advance(facts, now))
        |> settle(domain, now)

      facts.txt_ok == :unknown or facts.routing_ok == :unknown ->
        hold(now)

      expired?(domain, now) ->
        %{status: "expired", next_check_at: nil, last_error: dns_error(facts), checked_at: now}

      true ->
        retry(domain, dns_error(facts), now)
    end
  end

  def after_check(%{status: status} = domain, facts, now)
      when status in ["pending_tls", "active", "broken"] do
    cond do
      facts.routing_ok == :unknown ->
        hold(now)

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

  defp hold(now),
    do: %{checked_at: now, next_check_at: DateTime.add(now, @unknown_recheck_seconds, :second)}

  defp advance(%{tls_ok: true}, now),
    do: %{
      status: "active",
      active_at: now,
      attempts: 0,
      next_check_at: DateTime.add(now, @active_recheck_seconds, :second)
    }

  defp advance(_facts, now),
    do: %{attempts: 0, next_check_at: DateTime.add(now, hd(@backoff_seconds), :second)}

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
