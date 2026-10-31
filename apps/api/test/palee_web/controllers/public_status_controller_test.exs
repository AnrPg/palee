defmodule PaleeWeb.PublicStatusControllerTest do
  @moduledoc """
  ADR-364 over HTTP: the public status page data (no sign-in), incidents and
  maintenance from the platform console, the uptime history, and the
  double opt-in email subscription with its unsubscribe link.
  """

  use PaleeWeb.ConnCase, async: false
  use Palee.EmailCase

  import Palee.TestFixtures

  alias Palee.Application.{ServiceStatusJobs, ServiceStatusLinks, SignedToken}
  alias Palee.Infrastructure.Security.MemoryRateLimiter
  alias Palee.{Organizations, Repo, Status}
  alias Palee.Status.Subscriber

  setup do
    MemoryRateLimiter.reset!()
    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    {:ok, platform} = Organizations.resolve_platform_context(vendor)
    %{vendor: vendor, platform: platform}
  end

  defp json(conn), do: Plug.Conn.put_req_header(conn, "content-type", "application/json")

  defp sandbox(results) do
    Application.put_env(:palee, :status_sandbox_results, results)
    on_exit(fn -> Application.delete_env(:palee, :status_sandbox_results) end)
  end

  test "before any probe the page says unknown; after one, operational and cacheable", %{
    conn: conn
  } do
    assert %{"status" => "unknown", "components" => components} =
             conn |> get("/api/public/status") |> json_response(200)

    assert Enum.map(components, & &1["key"]) == ~w(app search files email payments fiscal)

    assert :ok = ServiceStatusJobs.probe()

    response = conn |> recycle() |> get("/api/public/status")

    assert %{"status" => "operational", "active" => [], "upcoming" => []} =
             json_response(response, 200)

    assert get_resp_header(response, "cache-control") == ["public, max-age=30"]
  end

  test "a failing probe shows publicly without its internal reason", %{conn: conn} do
    sandbox(%{"search" => {"down", "econnrefused meili:7700"}})
    :ok = ServiceStatusJobs.probe()

    body = conn |> get("/api/public/status") |> response(200)
    assert %{"status" => "partial_outage"} = Jason.decode!(body)
    refute body =~ "econnrefused"
  end

  test "an incident from the console is public, takes steps and is closed", ctx do
    :ok = ServiceStatusJobs.probe()

    incident =
      ctx.conn
      |> put_bearer_token(ctx.vendor)
      |> post("/api/platform/status/incidents", %{
        title: "Payments fail for some boxes",
        impact: "major",
        components: ["payments"],
        body: "We are looking into it."
      })
      |> json_response(201)

    assert %{"status" => "investigating", "updates" => [%{"body" => "We are looking into it."}]} =
             incident

    page = ctx.conn |> recycle() |> get("/api/public/status") |> json_response(200)
    assert page["status"] == "partial_outage"
    assert [%{"id" => id}] = page["active"]
    assert id == incident["id"]

    resolved =
      ctx.conn
      |> recycle()
      |> put_bearer_token(ctx.vendor)
      |> post("/api/platform/status/incidents/#{id}/updates", %{
        status: "resolved",
        body: "Fixed."
      })
      |> json_response(201)

    assert resolved["resolved_at"]
    assert [%{"status" => "resolved"}, %{"status" => "investigating"}] = resolved["updates"]

    assert %{"code" => "status_incident_closed"} =
             ctx.conn
             |> recycle()
             |> put_bearer_token(ctx.vendor)
             |> post("/api/platform/status/incidents/#{id}/updates", %{body: "Again"})
             |> json_response(409)

    assert %{"status" => "operational", "active" => []} =
             ctx.conn |> recycle() |> get("/api/public/status") |> json_response(200)

    history =
      ctx.conn |> recycle() |> get("/api/public/status/history?days=7") |> json_response(200)

    assert history["days"] == 7
    assert [%{"id" => ^id}] = history["incidents"]
    app = Enum.find(history["components"], &(&1["key"] == "app"))
    assert app["uptime_percent"] == 100.0
    assert length(app["days"]) == 7
    assert List.last(app["days"])["status"] == "operational"
  end

  test "planned maintenance is upcoming until its window", ctx do
    from = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

    ctx.conn
    |> put_bearer_token(ctx.vendor)
    |> post("/api/platform/status/incidents", %{
      kind: "maintenance",
      title: "Database upgrade",
      components: ["app"],
      scheduled_for: DateTime.to_iso8601(from),
      scheduled_until: DateTime.to_iso8601(DateTime.add(from, 1800)),
      body: "Palee will be read-only for up to 30 minutes."
    })
    |> json_response(201)

    assert %{"upcoming" => [%{"kind" => "maintenance", "status" => "scheduled"}], "active" => []} =
             ctx.conn |> recycle() |> get("/api/public/status") |> json_response(200)
  end

  test "only vendors use the console; bad input is refused", ctx do
    member = user_fixture()

    assert %{"code" => "vendor_required"} =
             ctx.conn
             |> put_bearer_token(member)
             |> get("/api/platform/status")
             |> json_response(403)

    assert %{"errors" => [%{"source" => %{"pointer" => "/components/0"}}]} =
             ctx.conn
             |> recycle()
             |> put_bearer_token(ctx.vendor)
             |> post("/api/platform/status/incidents", %{
               title: "Slow",
               body: "x",
               components: ["kitchen"]
             })
             |> json_response(422)

    console =
      ctx.conn
      |> recycle()
      |> put_bearer_token(ctx.vendor)
      |> get("/api/platform/status")
      |> json_response(200)

    assert %{"probes" => [], "subscribers" => %{"confirmed" => 0, "waiting" => 0}} = console
  end

  test "the console shows probe reasons and corrections need no note", ctx do
    sandbox(%{"email" => {"degraded", "3 emails deferred past the daily budget"}})
    :ok = ServiceStatusJobs.probe()

    console =
      ctx.conn
      |> put_bearer_token(ctx.vendor)
      |> get("/api/platform/status")
      |> json_response(200)

    email = Enum.find(console["probes"], &(&1["key"] == "email"))
    assert email["reason"] =~ "deferred"

    {:ok, incident, _update} =
      Status.create_incident(
        ctx.platform,
        %{title: "Slow search", body: "Looking"},
        DateTime.utc_now()
      )

    assert %{"impact" => "minor", "components" => ["search"]} =
             ctx.conn
             |> recycle()
             |> put_bearer_token(ctx.vendor)
             |> patch("/api/platform/status/incidents/#{incident.id}", %{
               impact: "minor",
               components: ["search"]
             })
             |> json_response(200)
  end

  describe "email subscriptions" do
    test "double opt-in, the same answer twice, emails on updates, one-click removal", ctx do
      assert %{"status" => "accepted"} =
               ctx.conn
               |> json()
               |> post("/api/public/status/subscriptions", %{email: "Owner@Box.gr", locale: "el"})
               |> json_response(202)

      confirm = assert_email_enqueued(kind: :status_subscription_confirm, to: "owner@box.gr")
      assert confirm.subject =~ "Επιβεβαίωσε"
      [_, token] = Regex.run(~r/\?confirm=([A-Za-z0-9_\-%]+)/, confirm.text)
      token = URI.decode_www_form(token)

      # Not confirmed yet: no status email goes out.
      {:ok, _incident, update} =
        Status.create_incident(
          ctx.platform,
          %{title: "Slow app", body: "Looking"},
          DateTime.utc_now()
        )

      assert {:ok, :done} = ServiceStatusJobs.notify(update.id, nil)
      refute_email_enqueued(kind: :status_update)

      assert %{"status" => "confirmed"} =
               ctx.conn
               |> recycle()
               |> json()
               |> post("/api/public/status/subscriptions/confirm", %{token: token})
               |> json_response(200)

      assert %{"code" => "status_subscription_not_found"} =
               ctx.conn
               |> recycle()
               |> json()
               |> post("/api/public/status/subscriptions/confirm", %{token: token})
               |> json_response(404)

      # Asking again for a confirmed address answers the same and sends nothing.
      assert %{"status" => "accepted"} =
               ctx.conn
               |> recycle()
               |> json()
               |> post("/api/public/status/subscriptions", %{email: "owner@box.gr"})
               |> json_response(202)

      assert [_one] = enqueued_emails(kind: :status_subscription_confirm)

      assert {:ok, :done} = ServiceStatusJobs.notify(update.id, nil)
      assert {:ok, :done} = ServiceStatusJobs.notify(update.id, nil)
      message = assert_email_enqueued(kind: :status_update, to: "owner@box.gr")
      assert message.subject =~ "Slow app"
      assert message.subject =~ "Διερευνάται"

      subscriber = Repo.get_by!(Subscriber, email: "owner@box.gr")
      assert message.text =~ ServiceStatusLinks.page_url() <> "?unsubscribe="
      refute message.text =~ "account"
      [_, signed] = Regex.run(~r/\?unsubscribe=(\S+)/, message.text)

      assert %{"status" => "removed"} =
               ctx.conn
               |> recycle()
               |> json()
               |> post("/api/public/status/subscriptions/unsubscribe", %{
                 token: URI.decode_www_form(signed)
               })
               |> json_response(200)

      assert Repo.get(Subscriber, subscriber.id) == nil
    end

    test "invalid addresses and tokens are refused", %{conn: conn} do
      assert conn
             |> json()
             |> json()
             |> post("/api/public/status/subscriptions", %{email: "nope"})
             |> json_response(422)

      assert %{"code" => "status_subscription_not_found"} =
               conn
               |> recycle()
               |> json()
               |> post("/api/public/status/subscriptions/unsubscribe", %{token: "forged"})
               |> json_response(404)

      forged = SignedToken.sign("another-salt", Ecto.UUID.generate())

      assert conn
             |> recycle()
             |> json()
             |> post("/api/public/status/subscriptions/unsubscribe", %{token: forged})
             |> json_response(404)
    end

    test "an expired sign-up cannot be confirmed and is swept" do
      token = "tok-#{System.unique_integer([:positive])}"
      old = DateTime.add(DateTime.utc_now(), -3, :day)
      {:ok, {:confirm, subscriber}} = Status.request_subscription("late@box.gr", "en", token, old)

      Repo.update_all(Subscriber, set: [updated_at: old, inserted_at: old])

      assert {:error, :status_subscription_not_found} =
               Status.confirm_subscription(token, DateTime.utc_now())

      assert %{unconfirmed: 1} = Status.sweep(DateTime.utc_now())
      assert Repo.get(Subscriber, subscriber.id) == nil
    end
  end
end
