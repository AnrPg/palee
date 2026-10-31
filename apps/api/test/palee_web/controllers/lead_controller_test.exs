defmodule PaleeWeb.LeadControllerTest do
  @moduledoc """
  ADR-344/345 end to end: an enquiry from the public form becomes a lead in
  the staff's «Ενδιαφερόμενοι»; staff move it, add notes and tasks, and it
  becomes a box member with its history kept. Spam is answered like an
  enquiry and stores nothing; consent is required and recorded.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.{Leads, Organizations}
  alias Palee.Infrastructure.Leads.{BoxSiteIntake, ProspectLeadSink}

  import Palee.TestFixtures

  setup do
    owner = admin_fixture(%{nickname: "lead_owner_#{System.unique_integer([:positive])}"})
    desk = user_fixture(%{role: :member})
    coach = user_fixture(%{role: :member})
    member = user_fixture(%{role: :member})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Lead Box #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, owner, :owner)
    add_tenant_member(organization, desk, :front_desk)
    add_tenant_member(organization, coach, :coach)
    add_tenant_member(organization, member, :member)

    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(owner_context, %{
        "about" => "Box",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(owner_context, %{"lock_version" => profile.lock_version})

    %{
      owner: owner,
      desk: desk,
      coach: coach,
      member: member,
      organization: organization,
      context: %{organization_id: organization.id}
    }
  end

  defp admin(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"

  defp public_post(conn, ctx, body) do
    ip =
      {10, 44, rem(System.unique_integer([:positive]), 250),
       rem(System.unique_integer([:positive]), 250)}

    %{conn | remote_ip: ip}
    |> put_req_header("content-type", "application/json")
    |> post("/api/public/boxes/#{ctx.organization.slug}/leads", Jason.encode!(body))
  end

  defp form(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Ελένη Παπά",
        "email" => "eleni.#{System.unique_integer([:positive])}@example.com",
        "phone" => "+30 694 000 1111",
        "message" => "Θέλω να δοκιμάσω ένα τμήμα",
        "kind" => "trial",
        "consent" => %{"contact" => true, "marketing" => false, "text_version" => "2027-05"},
        "form_started_at" => DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601()
      },
      overrides
    )
  end

  defp leads(conn, ctx, user, query \\ "") do
    conn
    |> put_bearer_token(user)
    |> get(admin(ctx, "/leads" <> query))
    |> json_response(200)
  end

  describe "the public form" do
    test "stores a lead with its consent, and the staff list shows it", %{conn: conn} = ctx do
      body = form()
      assert %{"status" => "received"} = conn |> public_post(ctx, body) |> json_response(202)

      %{"leads" => [lead], "counts" => counts} = leads(build_conn(), ctx, ctx.desk)
      assert lead["name"] == "Ελένη Παπά"
      assert lead["email"] == body["email"]
      assert lead["phone"] == "+306940001111"
      assert lead["source"] == "form"
      assert lead["stage"] == "new"
      assert lead["consent"]["contact_at"]
      assert lead["consent"]["marketing_at"] == nil
      assert lead["consent"]["text_version"] == "2027-05"
      assert counts["new"] == 1

      detail =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> get(admin(ctx, "/leads/#{lead["id"]}"))
        |> json_response(200)

      assert [%{"kind" => "created", "data" => data}] = detail["events"]
      assert data["kind"] == "trial"
      assert data["message"] == "Θέλω να δοκιμάσω ένα τμήμα"
    end

    test "the same address asking again joins the open lead", %{conn: conn} = ctx do
      body = form()
      conn |> public_post(ctx, body) |> json_response(202)

      build_conn()
      |> public_post(
        ctx,
        Map.merge(body, %{"consent" => %{"contact" => true, "marketing" => true}})
      )
      |> json_response(202)

      %{"leads" => [lead]} = leads(build_conn(), ctx, ctx.owner)
      assert lead["consent"]["marketing_at"]

      detail =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> get(admin(ctx, "/leads/#{lead["id"]}"))
        |> json_response(200)

      assert Enum.map(detail["events"], & &1["kind"]) |> Enum.sort() == [
               "created",
               "enquired_again"
             ]
    end

    test "spam is answered like an enquiry and stores nothing", %{conn: conn} = ctx do
      assert conn
             |> public_post(ctx, form(%{"website" => "http://spam.example"}))
             |> json_response(202)

      fast = form(%{"form_started_at" => DateTime.to_iso8601(DateTime.utc_now())})
      assert build_conn() |> public_post(ctx, fast) |> json_response(202)

      assert %{"leads" => []} = leads(build_conn(), ctx, ctx.owner)
    end

    test "contact consent is required; an unknown box is not found", %{conn: conn} = ctx do
      assert %{"code" => "validation_failed", "errors" => %{"consent" => ["contact_required"]}} =
               conn
               |> public_post(ctx, form(%{"consent" => %{"contact" => false}}))
               |> json_response(422)

      assert build_conn()
             |> Map.put(:remote_ip, {10, 45, 0, 1})
             |> put_req_header("content-type", "application/json")
             |> post(
               "/api/public/boxes/no-such-box-#{System.unique_integer([:positive])}/leads",
               Jason.encode!(form())
             )
             |> json_response(404)
    end
  end

  describe "the staff's list" do
    test "a lead from typing in to box member, its history kept", %{conn: conn} = ctx do
      created =
        conn
        |> put_bearer_token(ctx.desk)
        |> post(admin(ctx, "/leads"), %{
          "name" => "Κώστας Walk-in",
          "phone" => "6941112233",
          "source" => "walk_in",
          "owner_id" => ctx.desk.id
        })
        |> json_response(201)

      id = created["lead"]["id"]
      assert created["lead"]["owner"]["user_id"] == ctx.desk.id
      assert created["lead"]["consent"]["contact_at"]

      call = fn method, path, body ->
        build_conn()
        |> put_bearer_token(ctx.desk)
        |> then(
          &apply(Phoenix.ConnTest, :dispatch, [&1, @endpoint, method, admin(ctx, path), body])
        )
      end

      assert %{"lead" => %{"stage" => "trial"}} =
               call.(:post, "/leads/#{id}/move", %{"stage" => "trial"}) |> json_response(200)

      assert %{"code" => "invalid_lost_reason"} =
               call.(:post, "/leads/#{id}/move", %{"stage" => "lost"}) |> json_response(422)

      call.(:post, "/leads/#{id}/notes", %{"text" => "Ήρθε την Τρίτη"}) |> json_response(200)
      call.(:post, "/leads/#{id}/contacted", %{"channel" => "phone"}) |> json_response(200)

      due = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.to_iso8601()

      with_task =
        call.(:post, "/leads/#{id}/tasks", %{"title" => "Προσφορά 3μηνου", "due_at" => due})
        |> json_response(200)

      assert %{"title" => "Προσφορά 3μηνου", "id" => task_id} = with_task["lead"]["next_task"]

      assert %{"tasks" => [%{"lead_name" => "Κώστας Walk-in"}]} =
               build_conn()
               |> put_bearer_token(ctx.desk)
               |> get(admin(ctx, "/leads/tasks?mine=true"))
               |> json_response(200)

      done = call.(:post, "/leads/tasks/#{task_id}/done", %{}) |> json_response(200)
      assert done["lead"]["next_task"] == nil

      assert %{"code" => "lead_person_not_in_box"} =
               call.(:post, "/leads/#{id}/convert", %{"user_id" => user_fixture().id})
               |> json_response(422)

      converted =
        call.(:post, "/leads/#{id}/convert", %{"user_id" => ctx.member.id}) |> json_response(200)

      assert converted["lead"]["stage"] == "converted"
      assert converted["lead"]["person"]["user_id"] == ctx.member.id

      kinds = Enum.map(converted["events"], & &1["kind"])

      for kind <-
            ~w(created owner_changed stage_changed note contacted task_added task_done converted) do
        assert kind in kinds, kind
      end

      assert %{"code" => "lead_converted"} =
               call.(:post, "/leads/#{id}/move", %{"stage" => "new"}) |> json_response(409)
    end

    test "coaches have no leads; erasing a lead removes it", %{conn: conn} = ctx do
      assert conn
             |> put_bearer_token(ctx.coach)
             |> get(admin(ctx, "/leads"))
             |> json_response(403)

      %{"lead" => %{"id" => id}} =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> post(admin(ctx, "/leads"), %{"name" => "Σβήσε με", "email" => "erase@example.com"})
        |> json_response(201)

      assert build_conn()
             |> put_bearer_token(ctx.owner)
             |> delete(admin(ctx, "/leads/#{id}"))
             |> response(204)

      assert Leads.get(ctx.context, id) == nil
    end

    test "CSV import: a dry run writes nothing, the real one creates and joins",
         %{conn: conn} = ctx do
      csv = """
      Όνομα,Email,Τηλέφωνο
      Άννα,anna@example.com,
      Βασίλης,,6940000000
      ,nobody@example.com,
      """

      dry =
        conn
        |> put_bearer_token(ctx.owner)
        |> post(admin(ctx, "/leads/import"), %{"csv" => csv, "dry_run" => true})
        |> json_response(200)

      assert %{"dry_run" => true, "invalid" => 1, "created" => 0} = dry
      assert %{"leads" => []} = leads(build_conn(), ctx, ctx.owner)

      real =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> post(admin(ctx, "/leads/import"), %{"csv" => csv})
        |> json_response(200)

      assert %{"created" => 2, "invalid" => 1, "existing" => 0} = real

      again =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> post(admin(ctx, "/leads/import"), %{"csv" => csv})
        |> json_response(200)

      # Άννα has an email and joins her open lead; Βασίλης has only a phone.
      assert %{"existing" => 1, "created" => 1} = again
      assert %{"counts" => %{"new" => 3}} = leads(build_conn(), ctx, ctx.owner)
    end
  end

  describe "other ways in" do
    test "joining the box converts the person's open lead by email", ctx do
      person = user_fixture()

      {:ok, %{lead_id: lead_id, created: true}} =
        Palee.Application.Leads.CaptureLead.call(ctx.context, %{
          name: "Νέο μέλος",
          email: String.upcase(Palee.Identity.find_by_id(person.id).email),
          source: "manual"
        })

      add_tenant_member(ctx.organization, person, :member)

      lead = Leads.get(ctx.context, lead_id)
      assert lead.stage == "converted"
      assert lead.user_id == person.id

      assert Enum.any?(
               Leads.events(ctx.context, lead_id),
               &(&1.kind == "converted" and &1.data["via"] == "membership_activated")
             )
    end

    test "the box website's intake and the prospect assistant are idempotent", ctx do
      submission = Ecto.UUID.generate()

      intake = %{
        submission_id: submission,
        kind: "trial",
        source: "website_form",
        name: "Site Visitor",
        email: "visitor@example.com",
        phone: nil,
        message: nil,
        preferred_time: "Τρίτη απόγευμα",
        class_type_id: nil,
        locale: "el",
        marketing_opt_in: true,
        submitted_at: ~U[2027-05-01 10:00:00Z],
        attribution: %{utm_campaign: "spring"}
      }

      assert {:ok, %{lead_id: id}} = BoxSiteIntake.submit(ctx.context, intake)
      assert {:ok, %{lead_id: ^id}} = BoxSiteIntake.submit(ctx.context, intake)

      lead = Leads.get(ctx.context, id)
      assert lead.source == "website_form"
      assert lead.campaign == "spring"
      assert lead.interests == ["trial"]
      assert lead.consent_marketing_at == ~U[2027-05-01 10:00:00.000000Z]

      assert {:error, {:rejected, :invalid_lead}} =
               BoxSiteIntake.submit(ctx.context, %{
                 intake
                 | submission_id: Ecto.UUID.generate(),
                   email: nil
               })

      chat = %{
        name: "Chat Person",
        email: "chat@example.com",
        message: "Τιμές;",
        source_ref: "conv-1",
        language: "en",
        consent: %{
          contact: true,
          marketing: false,
          text_version: "a1",
          text_hash: "h",
          given_at: ~U[2027-05-01 10:00:00Z]
        }
      }

      assert {:ok, %{lead_id: chat_id}} = ProspectLeadSink.capture(ctx.context, chat)
      assert {:ok, %{lead_id: ^chat_id}} = ProspectLeadSink.capture(ctx.context, chat)
      assert Leads.get(ctx.context, chat_id).source == "prospect_assistant"
    end

    test "another box never sees the leads", ctx do
      {:ok, _} =
        Palee.Application.Leads.CaptureLead.call(ctx.context, %{
          name: "Δικός μας",
          email: "ours@example.com",
          source: "manual"
        })

      {:ok, other} =
        Organizations.create_organization(%{
          name: "Other Box #{System.unique_integer([:positive])}"
        })

      assert Leads.list(%{organization_id: other.id}, %{}) == []
      assert length(Leads.list(ctx.context, %{})) == 1
    end
  end

  defp add_tenant_member(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end
