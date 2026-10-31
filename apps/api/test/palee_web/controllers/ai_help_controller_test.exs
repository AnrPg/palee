defmodule PaleeWeb.AiHelpControllerTest do
  @moduledoc """
  ADR-361 and ADR-363 over HTTP, as the RLS-enforcing role: questions
  over the box's data (switch, rights, audit), the in-app support
  conversation with the AI first line and the hand-off, and the Palee
  team's ticket queue (audited).
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.AiHelpFixtures
  import Palee.TestFixtures

  alias Palee.Application.HelpCentre.SeedHelpCentre
  alias Palee.Infrastructure.Llm.SandboxLlmProvider
  alias Palee.Organizations
  alias Palee.Repo

  setup do
    on_exit(fn -> SandboxLlmProvider.script(nil) end)
    box = box_fixture()
    member = member_fixture(box, "member_#{System.unique_integer([:positive])}")
    class_fixture(box, "WOD", 30, [member])
    Map.merge(box, %{member: member, base: "/api/org/#{box.organization.slug}/admin"})
  end

  describe "data questions" do
    test "catalogue, ask, list and show", %{conn: conn, owner: owner, base: base, member: member} do
      catalogue =
        conn
        |> put_bearer_token(owner)
        |> get("#{base}/data-questions/catalogue")
        |> json_response(200)

      assert catalogue["enabled"]
      assert "members_absent" in Enum.map(catalogue["queries"], & &1["name"])

      answer =
        conn
        |> recycle()
        |> put_bearer_token(owner)
        |> post("#{base}/data-questions", %{
          question: "Who hasn't come for 3 weeks?",
          locale: "en"
        })
        |> json_response(200)

      assert answer["status"] == "answered"
      assert [%{"query" => "members_absent"}] = answer["citations"]
      assert [%{"rows" => [%{"name" => name}]}] = answer["tables"]
      assert name == member.nickname

      listed =
        conn
        |> recycle()
        |> put_bearer_token(owner)
        |> get("#{base}/data-questions")
        |> json_response(200)

      assert [%{"id" => id}] = listed["questions"]
      assert id == answer["id"]

      shown =
        conn
        |> recycle()
        |> put_bearer_token(owner)
        |> get("#{base}/data-questions/#{id}")
        |> json_response(200)

      assert shown["queries"] == ["members_absent"]
    end

    test "off until the box turns it on", %{conn: conn} do
      box = box_fixture(enabled: false)

      response =
        conn
        |> put_bearer_token(box.owner)
        |> post("/api/org/#{box.organization.slug}/admin/data-questions", %{
          question: "Revenue last month?"
        })

      assert %{"code" => "data_questions_disabled"} = json_response(response, 403)
    end

    test "someone outside the box's staff cannot ask", %{conn: conn, member: member, base: base} do
      response =
        conn
        |> put_bearer_token(member)
        |> post("#{base}/data-questions", %{question: "Revenue?"})

      assert response.status in [403, 404]
    end
  end

  describe "in-app support" do
    setup do
      {:ok, _counts} = SeedHelpCentre.call()
      vendor = user_fixture(%{nickname: "support_vendor_#{System.unique_integer([:positive])}"})
      {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
      %{vendor: vendor}
    end

    test "the AI first line answers from articles, then the Palee team takes over", ctx do
      %{conn: conn, owner: owner, base: base, vendor: vendor} = ctx

      started =
        conn
        |> put_bearer_token(owner)
        |> post("#{base}/help-desk/conversations", %{
          message: "How do I start a campaign with coupons?",
          screen_path: "/admin/finance",
          locale: "en"
        })
        |> json_response(200)

      assert started["assistant"] == "answered"
      assert started["can_hand_off"]

      assert [_person, %{"author" => "assistant", "citations" => [cited | _]}] =
               started["messages"]

      assert cited["slug"] == "guide-finance-offers"
      id = started["id"]

      handed =
        conn
        |> recycle()
        |> put_bearer_token(owner)
        |> post("#{base}/help-desk/conversations/#{id}/hand-off", %{
          note: "The coupon does not apply at checkout",
          priority: "urgent",
          client_context: %{app_version: "3.1.0", platform: "web"}
        })
        |> json_response(200)

      assert handed["status"] == "waiting_for_palee"
      refute handed["can_hand_off"]
      assert %{"status" => "open", "priority" => "urgent", "id" => ticket_id} = handed["ticket"]

      # The Palee team works the queue; reading a ticket is audited.
      queue =
        conn
        |> recycle()
        |> put_bearer_token(vendor)
        |> get("/api/platform/help-desk/tickets", %{status: "open"})
        |> json_response(200)

      assert ticket_id in Enum.map(queue["tickets"], & &1["id"])

      ticket =
        conn
        |> recycle()
        |> put_bearer_token(vendor)
        |> get("/api/platform/help-desk/tickets/#{ticket_id}")
        |> json_response(200)

      assert ticket["client_context"] == %{"app_version" => "3.1.0", "platform" => "web"}
      assert ticket["articles_tried"] != []
      assert length(ticket["messages"]) == 2

      replied =
        conn
        |> recycle()
        |> put_bearer_token(vendor)
        |> post("/api/platform/help-desk/tickets/#{ticket_id}/replies", %{
          body: "Fixed on our side, try again."
        })
        |> json_response(200)

      assert replied["status"] == "waiting_on_box"
      assert replied["assignee_id"] == vendor.id

      events =
        Repo.all(Palee.Organizations.OrganizationProvisioningEvent)
        |> Enum.filter(&(&1.organization_id == ctx.organization.id))
        |> Enum.map(& &1.event)

      assert "help_desk_ticket_viewed" in events and "help_desk_ticket_replied" in events

      # The person sees the reply; their next message goes to the team, not the AI.
      followed =
        conn
        |> recycle()
        |> put_bearer_token(owner)
        |> post("#{base}/help-desk/conversations/#{id}/messages", %{message: "Works now, thanks!"})
        |> json_response(200)

      assert followed["assistant"] == "skipped"
      assert Enum.map(followed["messages"], & &1["author"]) == ~w(person assistant palee person)
      assert followed["ticket"]["status"] == "open"

      resolved =
        conn
        |> recycle()
        |> put_bearer_token(owner)
        |> post("#{base}/help-desk/conversations/#{id}/resolve")
        |> json_response(200)

      assert resolved["status"] == "resolved"
      assert resolved["ticket"]["status"] == "solved"
    end

    test "conversations are the person's own", %{
      conn: conn,
      owner: owner,
      base: base,
      organization: organization
    } do
      started =
        conn
        |> put_bearer_token(owner)
        |> post("#{base}/help-desk/conversations", %{
          message: "zzqx unrelated words",
          locale: "en"
        })
        |> json_response(200)

      assert started["assistant"] == "no_articles"

      colleague = admin_fixture()

      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: colleague.id,
          role: :owner,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      assert conn
             |> recycle()
             |> put_bearer_token(colleague)
             |> get("#{base}/help-desk/conversations/#{started["id"]}")
             |> json_response(404)

      assert %{"conversations" => []} =
               conn
               |> recycle()
               |> put_bearer_token(colleague)
               |> get("#{base}/help-desk/conversations")
               |> json_response(200)

      assert %{"conversations" => [_]} =
               conn
               |> recycle()
               |> put_bearer_token(owner)
               |> get("#{base}/help-desk/conversations")
               |> json_response(200)
    end

    test "provider down or past the daily limit: the hand-off is offered", %{
      conn: conn,
      owner: owner,
      base: base
    } do
      SandboxLlmProvider.script(fn _request -> {:error, :llm_unavailable} end)

      ask = %{
        message: "How do I start a campaign with coupons?",
        screen_path: "/admin/finance",
        locale: "en"
      }

      down =
        conn
        |> put_bearer_token(owner)
        |> post("#{base}/help-desk/conversations", ask)
        |> json_response(200)

      assert down["assistant"] == "unavailable"
      assert down["can_hand_off"]
      assert Enum.map(down["messages"], & &1["author"]) == ["person"]

      SandboxLlmProvider.script(nil)
      previous = Application.get_env(:palee, :ai_features)
      on_exit(fn -> Application.put_env(:palee, :ai_features, previous) end)

      Application.put_env(
        :palee,
        :ai_features,
        Keyword.put(previous, :help_desk,
          monthly_budget_nano_usd: 3_000_000_000,
          daily_per_person: 1
        )
      )

      limited =
        conn
        |> recycle()
        |> put_bearer_token(owner)
        |> post("#{base}/help-desk/conversations", ask)
        |> json_response(200)

      assert limited["assistant"] == "limit_reached"
    end

    test "only vendors see the queue", %{conn: conn, owner: owner} do
      assert %{"code" => "vendor_required"} =
               conn
               |> put_bearer_token(owner)
               |> get("/api/platform/help-desk/tickets")
               |> json_response(403)
    end
  end
end
