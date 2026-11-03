defmodule Palee.Infrastructure.BoxSite.KubernetesSiteIngress do
  @moduledoc """
  ADR-398: custom hosts as Ingresses in Palee's own namespace, through the
  Kubernetes API with the pod's service account (in-cluster config). The
  Ingress carries a cert-manager annotation, so cert-manager's ingress-shim
  creates the Certificate (named like the TLS secret) and solves HTTP-01
  through the same ingress controller; Palee only reads that Certificate.

  One Ingress per host, named `palee-site-<hash>` (the host is in the
  `palee.app/site-host` annotation, labels cannot hold 253 characters).
  `/api` goes to the API, everything else to the web, which serves the box's
  site for that host and sends a secondary host to the primary one.

  Configuration, `config :palee, :box_site_kubernetes`:

    * `api_url` (default `https://kubernetes.default.svc`),
      `namespace` (default: the service account's), `token_path`,
      `ca_path`; `token` only in tests;
    * `issuer_kind` (`"Issuer"` or `"ClusterIssuer"`), `issuer_name`;
    * `ingress_class` (`nil` uses the cluster's default class);
    * `api_service`/`api_port`, `web_service`/`web_port`;
    * `req_options` (tests use `Req.Test`).

  The token is read on every call (projected tokens rotate) and never
  logged.
  """

  @behaviour Palee.BoxSite.Ports.SiteIngress

  @sa_dir "/var/run/secrets/kubernetes.io/serviceaccount"
  @field_manager "palee-api"
  @site_label "palee.app/site"
  @host_annotation "palee.app/site-host"

  # ── Port ────────────────────────────────────────────────────────────────

  @impl true
  def apply_site(host) do
    config = config()

    request(config,
      method: :patch,
      url:
        ingress_url(config, ingress_name(host)) <>
          "?fieldManager=#{@field_manager}&force=true",
      headers: [{"content-type", "application/apply-patch+yaml"}],
      body: Jason.encode!(manifest(host, config))
    )
    |> case do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      other -> failure(other)
    end
  end

  @impl true
  def remove_site(host) do
    config = config()

    case request(config, method: :delete, url: ingress_url(config, ingress_name(host))) do
      {:ok, %{status: status}} when status in 200..299 or status == 404 -> :ok
      other -> failure(other)
    end
  end

  @impl true
  def certificate(host) do
    config = config()

    url =
      "#{api_url(config)}/apis/cert-manager.io/v1/namespaces/#{namespace(config)}/certificates/" <>
        secret_name(host)

    case request(config, method: :get, url: url) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, certificate_state(body)}
      # ingress-shim has not made it yet.
      {:ok, %{status: 404}} -> {:ok, :issuing}
      other -> failure(other)
    end
  end

  @impl true
  def managed_hosts do
    config = config()
    url = ingress_url(config, nil) <> "?labelSelector=" <> URI.encode_www_form("#{@site_label}=true")

    case request(config, method: :get, url: url) do
      {:ok, %{status: 200, body: %{"items" => items}}} when is_list(items) ->
        {:ok,
         items
         |> Enum.map(&get_in(&1, ["metadata", "annotations", @host_annotation]))
         |> Enum.filter(&is_binary/1)}

      other ->
        failure(other)
    end
  end

  # ── Manifest ────────────────────────────────────────────────────────────

  @doc "The Ingress's name for a host (DNS-label safe, stable)."
  def ingress_name(host) do
    hash = :crypto.hash(:sha256, host) |> Base.encode16(case: :lower) |> binary_part(0, 20)
    "palee-site-" <> hash
  end

  @doc "The TLS secret (and the Certificate ingress-shim names after it)."
  def secret_name(host), do: ingress_name(host) <> "-tls"

  @doc "The Ingress Palee applies for a host."
  def manifest(host, config \\ config()) do
    issuer_annotation =
      if Keyword.get(config, :issuer_kind, "Issuer") == "ClusterIssuer",
        do: "cert-manager.io/cluster-issuer",
        else: "cert-manager.io/issuer"

    spec =
      %{
        "tls" => [%{"hosts" => [host], "secretName" => secret_name(host)}],
        "rules" => [
          %{
            "host" => host,
            "http" => %{
              "paths" => [
                path("/api", Keyword.get(config, :api_service, "palee-api"), Keyword.get(config, :api_port, 4000)),
                path("/", Keyword.get(config, :web_service, "palee-web"), Keyword.get(config, :web_port, 3000))
              ]
            }
          }
        ]
      }
      |> maybe_put("ingressClassName", Keyword.get(config, :ingress_class))

    %{
      "apiVersion" => "networking.k8s.io/v1",
      "kind" => "Ingress",
      "metadata" => %{
        "name" => ingress_name(host),
        "labels" => %{
          @site_label => "true",
          "app.kubernetes.io/managed-by" => @field_manager
        },
        "annotations" => %{
          @host_annotation => host,
          issuer_annotation => Keyword.get(config, :issuer_name, "palee-sites")
        }
      },
      "spec" => spec
    }
  end

  defp path(prefix, service, port) do
    %{
      "path" => prefix,
      "pathType" => "Prefix",
      "backend" => %{"service" => %{"name" => service, "port" => %{"number" => port}}}
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ── Certificate status ──────────────────────────────────────────────────

  @doc """
  A cert-manager Certificate as the card needs it: `:active` once Ready,
  `{:failed, reason}` after a failed issuance that is not being retried
  right now, `:issuing` otherwise.
  """
  def certificate_state(%{} = certificate) do
    status = Map.get(certificate, "status") || %{}
    conditions = Map.get(status, "conditions") || []
    ready = condition(conditions, "Ready")
    issuing = condition(conditions, "Issuing")

    cond do
      ready && ready["status"] == "True" ->
        :active

      issuing && issuing["status"] == "True" ->
        :issuing

      (issuing && issuing["reason"] == "Failed") || Map.has_key?(status, "lastFailureTime") ->
        message = (issuing && issuing["message"]) || (ready && ready["message"]) || ""
        {:failed, failure_reason(message)}

      true ->
        :issuing
    end
  end

  defp condition(conditions, type), do: Enum.find(conditions, &(&1["type"] == type))

  @doc "A plain reason from cert-manager's failure message."
  def failure_reason(message) do
    text = String.downcase(message || "")

    cond do
      String.contains?(text, ["ratelimited", "rate limit", "too many"]) ->
        :rate_limited

      String.contains?(text, "issuer") and String.contains?(text, ["not found", "not ready"]) ->
        :issuer_not_ready

      String.contains?(text, [
        "challenge",
        "acme:error:unauthorized",
        "acme:error:connection",
        "acme:error:dns",
        "propagation"
      ]) ->
        :challenge_failed

      true ->
        :issuance_failed
    end
  end

  # ── HTTP ────────────────────────────────────────────────────────────────

  defp request(config, options) do
    with {:ok, token} <- token(config) do
      [
        headers: [{"authorization", "Bearer " <> token}, {"accept", "application/json"}],
        receive_timeout: 15_000,
        retry: false
      ]
      |> Keyword.merge(ca_options(config))
      |> merge_request(options)
      |> Keyword.merge(Keyword.get(config, :req_options, []))
      |> Req.request()
    end
  end

  defp merge_request(defaults, options) do
    headers = Keyword.get(defaults, :headers, []) ++ Keyword.get(options, :headers, [])
    defaults |> Keyword.merge(options) |> Keyword.put(:headers, headers)
  end

  defp failure({:ok, %{status: status}}) when status in [401, 403, 404, 409, 422],
    do: {:error, {:refused, {:http, status}}}

  defp failure({:ok, %{status: status}}), do: {:error, {:transient, {:http, status}}}
  defp failure({:error, {kind, _reason} = error}) when kind in [:refused, :transient], do: {:error, error}
  defp failure({:error, _exception}), do: {:error, {:transient, :unreachable}}

  defp token(config) do
    case Keyword.get(config, :token) do
      token when is_binary(token) ->
        {:ok, token}

      _file ->
        case File.read(Keyword.get(config, :token_path, @sa_dir <> "/token")) do
          {:ok, token} -> {:ok, String.trim(token)}
          {:error, _reason} -> {:error, {:refused, :no_service_account}}
        end
    end
  end

  defp ca_options(config) do
    path = Keyword.get(config, :ca_path, @sa_dir <> "/ca.crt")

    if File.exists?(path),
      do: [connect_options: [transport_opts: [cacertfile: path]]],
      else: []
  end

  defp ingress_url(config, nil),
    do: "#{api_url(config)}/apis/networking.k8s.io/v1/namespaces/#{namespace(config)}/ingresses"

  defp ingress_url(config, name), do: ingress_url(config, nil) <> "/" <> name

  # The service's DNS name: the API server's certificate names it, while
  # checking a certificate against the bare service IP is not reliable.
  defp api_url(config), do: Keyword.get(config, :api_url) || "https://kubernetes.default.svc"

  defp namespace(config) do
    Keyword.get_lazy(config, :namespace, fn ->
      case File.read(@sa_dir <> "/namespace") do
        {:ok, namespace} -> String.trim(namespace)
        {:error, _reason} -> "default"
      end
    end)
  end

  defp config, do: Application.get_env(:palee, :box_site_kubernetes, [])
end
