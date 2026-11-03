defmodule Palee.Infrastructure.BoxSite.KubernetesSiteIngressTest do
  @moduledoc "ADR-398: the Kubernetes adapter behind `BoxSite.Ports.SiteIngress` (API stubbed)."

  use ExUnit.Case, async: false

  alias Palee.Infrastructure.BoxSite.KubernetesSiteIngress

  @host "www.mybox.gr"

  setup do
    previous = Application.get_env(:palee, :box_site_kubernetes)

    Application.put_env(:palee, :box_site_kubernetes,
      api_url: "https://k8s.test",
      namespace: "tenant-m4",
      token: "sa-token",
      ca_path: "/nonexistent/ca.crt",
      issuer_kind: "Issuer",
      issuer_name: "palee-sites",
      ingress_class: nil,
      api_service: "palee-api",
      api_port: 4000,
      web_service: "palee-web",
      web_port: 3000,
      req_options: [plug: {Req.Test, __MODULE__}, retry: false]
    )

    on_exit(fn -> Application.put_env(:palee, :box_site_kubernetes, previous) end)
    :ok
  end

  test "names are stable, DNS-safe and per host" do
    name = KubernetesSiteIngress.ingress_name(@host)
    assert name =~ ~r/^palee-site-[0-9a-f]{20}$/
    assert name == KubernetesSiteIngress.ingress_name(@host)
    refute name == KubernetesSiteIngress.ingress_name("mybox.gr")
    assert KubernetesSiteIngress.secret_name(@host) == name <> "-tls"
  end

  test "the manifest routes /api to the API and the rest to the web, with the issuer" do
    manifest = KubernetesSiteIngress.manifest(@host, issuer_kind: "Issuer", issuer_name: "palee-sites")

    assert manifest["metadata"]["annotations"] == %{
             "palee.app/site-host" => @host,
             "cert-manager.io/issuer" => "palee-sites"
           }

    assert manifest["metadata"]["labels"]["palee.app/site"] == "true"
    refute Map.has_key?(manifest["spec"], "ingressClassName")
    assert [%{"hosts" => [@host], "secretName" => secret}] = manifest["spec"]["tls"]
    assert secret == KubernetesSiteIngress.secret_name(@host)

    assert [%{"host" => @host, "http" => %{"paths" => [api, web]}}] = manifest["spec"]["rules"]
    assert api["path"] == "/api" and api["backend"]["service"] == %{"name" => "palee-api", "port" => %{"number" => 4000}}
    assert web["path"] == "/" and web["backend"]["service"]["name"] == "palee-web"

    cluster =
      KubernetesSiteIngress.manifest(@host,
        issuer_kind: "ClusterIssuer",
        issuer_name: "letsencrypt-production",
        ingress_class: "nginx"
      )

    assert cluster["metadata"]["annotations"]["cert-manager.io/cluster-issuer"] == "letsencrypt-production"
    assert cluster["spec"]["ingressClassName"] == "nginx"
  end

  test "apply is a server-side apply with the service account token" do
    name = KubernetesSiteIngress.ingress_name(@host)

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/apis/networking.k8s.io/v1/namespaces/tenant-m4/ingresses/#{name}"
      assert conn.query_string == "fieldManager=palee-api&force=true"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sa-token"]
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/apply-patch+yaml"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"kind" => "Ingress", "metadata" => %{"name" => ^name}} = Jason.decode!(body)
      Req.Test.json(conn, %{"kind" => "Ingress"})
    end)

    assert KubernetesSiteIngress.apply_site(@host) == :ok
  end

  test "refusals and outages are told apart" do
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 403, "forbidden"))
    assert KubernetesSiteIngress.apply_site(@host) == {:error, {:refused, {:http, 403}}}

    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 503, "busy"))
    assert KubernetesSiteIngress.apply_site(@host) == {:error, {:transient, {:http, 503}}}

    Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))
    assert KubernetesSiteIngress.apply_site(@host) == {:error, {:transient, :unreachable}}
  end

  test "without a token nothing is called" do
    config = Application.get_env(:palee, :box_site_kubernetes)

    Application.put_env(
      :palee,
      :box_site_kubernetes,
      config |> Keyword.delete(:token) |> Keyword.put(:token_path, "/nonexistent/token")
    )

    assert KubernetesSiteIngress.apply_site(@host) == {:error, {:refused, :no_service_account}}
  end

  test "remove deletes the Ingress; one already gone is fine" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      Plug.Conn.send_resp(conn, 404, "{}")
    end)

    assert KubernetesSiteIngress.remove_site(@host) == :ok
  end

  test "the certificate: missing, issuing, ready and failed" do
    secret = KubernetesSiteIngress.secret_name(@host)

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path ==
               "/apis/cert-manager.io/v1/namespaces/tenant-m4/certificates/#{secret}"

      Plug.Conn.send_resp(conn, 404, "{}")
    end)

    assert KubernetesSiteIngress.certificate(@host) == {:ok, :issuing}

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "status" => %{"conditions" => [%{"type" => "Ready", "status" => "True"}]}
      })
    end)

    assert KubernetesSiteIngress.certificate(@host) == {:ok, :active}

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "status" => %{
          "lastFailureTime" => "2026-11-03T10:00:00Z",
          "conditions" => [
            %{"type" => "Ready", "status" => "False", "reason" => "DoesNotExist"},
            %{
              "type" => "Issuing",
              "status" => "False",
              "reason" => "Failed",
              "message" =>
                "The certificate request has failed to complete and will be retried: acme: authorization error for www.mybox.gr: 403 urn:ietf:params:acme:error:unauthorized"
            }
          ]
        }
      })
    end)

    assert KubernetesSiteIngress.certificate(@host) == {:ok, {:failed, :challenge_failed}}
  end

  test "certificate states and plain reasons" do
    issuing = %{"status" => %{"conditions" => [%{"type" => "Issuing", "status" => "True"}]}}
    assert KubernetesSiteIngress.certificate_state(issuing) == :issuing
    assert KubernetesSiteIngress.certificate_state(%{}) == :issuing

    # A renewal that failed keeps the old certificate: still active.
    renewing = %{
      "status" => %{
        "lastFailureTime" => "2026-11-03T10:00:00Z",
        "conditions" => [%{"type" => "Ready", "status" => "True"}]
      }
    }

    assert KubernetesSiteIngress.certificate_state(renewing) == :active

    assert KubernetesSiteIngress.failure_reason("429 urn:ietf:params:acme:error:rateLimited: too many certificates") ==
             :rate_limited

    assert KubernetesSiteIngress.failure_reason("issuer.cert-manager.io \"palee-sites\" not found") ==
             :issuer_not_ready

    assert KubernetesSiteIngress.failure_reason("Waiting for HTTP-01 challenge propagation") ==
             :challenge_failed

    assert KubernetesSiteIngress.failure_reason("something else") == :issuance_failed
    assert KubernetesSiteIngress.failure_reason(nil) == :issuance_failed
  end

  test "managed hosts come from the label and the host annotation" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/apis/networking.k8s.io/v1/namespaces/tenant-m4/ingresses"
      assert conn.query_string == "labelSelector=palee.app%2Fsite%3Dtrue"

      Req.Test.json(conn, %{
        "items" => [
          %{"metadata" => %{"annotations" => %{"palee.app/site-host" => @host}}},
          %{"metadata" => %{"name" => "stray"}}
        ]
      })
    end)

    assert KubernetesSiteIngress.managed_hosts() == {:ok, [@host]}
  end
end
