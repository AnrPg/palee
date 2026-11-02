defmodule PaleeWeb.PlatformStatusControllerTest do
  @moduledoc """
  ADR-366 over HTTP: the console previews an incident in English (sandbox
  translator), publishes it with its source language and English copy, shows
  who published it, and publishes untranslated when the translator fails.
  Subscribers read the original in its language and English otherwise.
  """

  use PaleeWeb.ConnCase, async: false
  use Palee.EmailCase

  import Palee.TestFixtures

  alias Palee.Application.ServiceStatusJobs
  alias Palee.Infrastructure.Security.MemoryRateLimiter
  alias Palee.{Organizations, Repo, Status}
  alias Palee.Status.{IncidentUpdate, Subscriber}

  setup do
    MemoryRateLimiter.reset!()
    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    %{vendor: vendor}
  end

  defp fail_translation do
    Application.put_env(:palee, :status_sandbox_translation, {:error, :timeout})
    on_exit(fn -> Application.delete_env(:palee, :status_sandbox_translation) end)
  end

  test "a vendor previews the English text; English stays as it is", ctx do
    assert %{"locale" => "el", "title" => "[EN] Καθυστερήσεις", "body" => "[EN] Το ερευνούμε."} =
             ctx.conn
             |> put_bearer_token(ctx.vendor)
             |> post("/api/platform/status/translations", %{
               title: "Καθυστερήσεις",
               body: "Το ερευνούμε."
             })
             |> json_response(200)

    assert %{"locale" => "en", "title" => nil, "body" => "Fixed."} =
             ctx.conn
             |> recycle()
             |> put_bearer_token(ctx.vendor)
             |> post("/api/platform/status/translations", %{body: "Fixed."})
             |> json_response(200)
  end

  test "a failed translation says so; members cannot ask", ctx do
    fail_translation()

    assert %{"code" => "status_translation_unavailable"} =
             ctx.conn
             |> put_bearer_token(ctx.vendor)
             |> post("/api/platform/status/translations", %{body: "Το ερευνούμε."})
             |> json_response(503)

    assert %{"code" => "vendor_required"} =
             ctx.conn
             |> recycle()
             |> put_bearer_token(user_fixture())
             |> post("/api/platform/status/translations", %{body: "x"})
             |> json_response(403)
  end

  test "an incident keeps its language and English copy and shows its publisher", ctx do
    incident =
      ctx.conn
      |> put_bearer_token(ctx.vendor)
      |> post("/api/platform/status/incidents", %{
        title: "Καθυστερήσεις στα email",
        impact: "minor",
        components: ["email"],
        body: "Τα αποδεικτικά φεύγουν με καθυστέρηση.",
        locale: "el",
        title_en: "Email delays",
        body_en: "Receipts are delayed.",
        en_source: "edited",
        notify: false
      })
      |> json_response(201)

    assert %{
             "locale" => "el",
             "title_en" => "Email delays",
             "en_source" => "edited",
             "published_by" => publisher,
             "updates" => [%{"body_en" => "Receipts are delayed.", "published_by" => publisher}]
           } = incident

    assert publisher == ctx.vendor.nickname

    step =
      ctx.conn
      |> recycle()
      |> put_bearer_token(ctx.vendor)
      |> post("/api/platform/status/incidents/#{incident["id"]}/updates", %{
        status: "monitoring",
        body: "Διορθώθηκε, παρακολουθούμε.",
        locale: "el",
        body_en: "Fixed, monitoring.",
        notify: false
      })
      |> json_response(201)

    assert [%{"body_en" => "Fixed, monitoring.", "en_source" => "auto"} | _] = step["updates"]

    console =
      ctx.conn
      |> recycle()
      |> put_bearer_token(ctx.vendor)
      |> get("/api/platform/status")
      |> json_response(200)

    assert [%{"published_by" => ^publisher}] = console["incidents"]

    public = ctx.conn |> recycle() |> get("/api/public/status") |> response(200)
    assert %{"active" => [%{"title_en" => "Email delays"} = active]} = Jason.decode!(public)
    refute Map.has_key?(active, "published_by")
  end

  test "without a translation the incident is published in its own language", ctx do
    fail_translation()

    assert %{"title_en" => nil, "en_source" => nil, "updates" => [%{"body_en" => nil}]} =
             ctx.conn
             |> put_bearer_token(ctx.vendor)
             |> post("/api/platform/status/incidents", %{
               title: "Καθυστερήσεις",
               body: "Το ερευνούμε.",
               locale: "el",
               notify: false
             })
             |> json_response(201)

    assert %{"code" => "invalid_status_translation"} =
             ctx.conn
             |> recycle()
             |> put_bearer_token(ctx.vendor)
             |> post("/api/platform/status/incidents", %{
               title: "Καθυστερήσεις",
               body: "Το ερευνούμε.",
               locale: "el",
               title_en: "Delays"
             })
             |> json_response(422)
  end

  test "subscribers read the original in its language and English otherwise", ctx do
    for {email, locale} <- [{"el-reader@example.com", "el"}, {"de-reader@example.com", "de"}] do
      {:ok, {:confirm, subscriber}} =
        Status.request_subscription(email, locale, "token-#{locale}", DateTime.utc_now())

      subscriber |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now()) |> Repo.update!()
    end

    incident =
      ctx.conn
      |> put_bearer_token(ctx.vendor)
      |> post("/api/platform/status/incidents", %{
        title: "Καθυστερήσεις στα email",
        body: "Το ερευνούμε.",
        locale: "el",
        title_en: "Email delays",
        body_en: "We are looking into it.",
        notify: false
      })
      |> json_response(201)

    [%{"id" => update_id}] = incident["updates"]
    assert %IncidentUpdate{} = Repo.get(IncidentUpdate, update_id)
    assert {:ok, :done} = ServiceStatusJobs.notify(update_id, nil)

    greek = assert_email_enqueued(kind: :status_update, to: "el-reader@example.com")
    german = assert_email_enqueued(kind: :status_update, to: "de-reader@example.com")
    assert greek.subject =~ "Καθυστερήσεις στα email"
    assert greek.text =~ "Το ερευνούμε."
    assert german.subject =~ "Email delays"
    assert german.text =~ "We are looking into it."
    assert Repo.aggregate(Subscriber, :count) >= 2
  end
end
