defmodule PaleeWeb.BoxSiteTemplatesTest do
  @moduledoc """
  ADR-530 end to end, as the RLS runtime role: the look and the section
  switches wait in a draft until «Δημοσίευση», the preview shows the draft,
  the notice of a moved site, and the new public sections (photos, community
  numbers, programmes).
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  import Palee.TestSupport.ImageFixtures

  alias Palee.Application.{
    CompleteMediaUpload,
    CreatePR,
    PublishBoxPublicProfile,
    RequestMediaUpload,
    UpdateBoxPublicProfile
  }

  alias Palee.Application.BoxSite.SiteTemplateNotice
  alias Palee.{BoxSite, Media, Organizations, Repo}
  alias Palee.Identity.UserContext
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.TestSupport.MemoryObjectStore

  setup do
    MemoryObjectStore.start()
    owner = admin_fixture()
    member = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Look Box #{System.unique_integer([:positive])}"})

    for {user, role} <- [{owner, :owner}, {member, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    %{
      owner: owner,
      member: member,
      organization: organization,
      context: context,
      admin: "/api/org/#{organization.slug}/admin/site",
      public: "/api/public/sites/#{organization.slug}"
    }
  end

  defp owner_conn(ctx), do: put_bearer_token(build_conn(), ctx.owner)

  defp publish_page!(ctx, params \\ %{}) do
    {:ok, profile} =
      UpdateBoxPublicProfile.call(
        ctx.context,
        Map.merge(%{"about" => "Box", "disciplines" => ["crossfit"]}, params)
      )

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(ctx.context, %{"lock_version" => profile.lock_version})
  end

  defp upload!(context) do
    body = jpeg(40, 30)

    {:ok, upload} =
      RequestMediaUpload.call(context, "box_photo", %{
        "content_type" => "image/jpeg",
        "byte_size" => byte_size(body)
      })

    media = Media.get(context, :tenant, upload.media_id)
    :ok = MemoryObjectStore.put_object(:media_public, media.object_key, body, "image/jpeg")
    {:ok, _ready} = CompleteMediaUpload.call(context, "box_photo", upload.media_id)
    upload.media_id
  end

  test "the look waits for «Δημοσίευση»; discard throws it away", ctx do
    publish_page!(ctx)

    site = build_conn() |> get(ctx.public) |> json_response(200)

    assert %{
             "template" => "tiles",
             "palette" => "palee",
             "appearance" => "auto",
             "calm_motion" => false,
             "phone" => nil,
             "programmes" => [],
             "photos" => %{"items" => [], "video" => nil}
           } = site

    # Nothing to count yet: the section hides.
    refute "stats" in site["sections"]
    assert site["stats"] == nil

    %{"settings" => settings} =
      ctx
      |> owner_conn()
      |> put(ctx.admin, %{
        lock_version: 0,
        template: "atelier",
        palette: "emerald",
        appearance: "dark",
        calm_motion: true,
        hidden_sections: ["faq"],
        forms_enabled: false
      })
      |> json_response(200)

    assert settings["template"] == "tiles" and settings["forms_enabled"] == false

    assert settings["draft"] == %{
             "template" => "atelier",
             "palette" => "emerald",
             "appearance" => "dark",
             "calm_motion" => true,
             "hidden_sections" => ["faq"]
           }

    # Visitors still see the live look; the form switch is live at once.
    site = build_conn() |> get(ctx.public) |> json_response(200)
    assert site["template"] == "tiles" and site["forms"]["trial"] == false

    # Staff preview the draft.
    preview = ctx |> owner_conn() |> get("#{ctx.admin}/preview") |> json_response(200)

    assert %{"template" => "atelier", "palette" => "emerald", "calm_motion" => true} = preview
    assert preview["slug"] == ctx.organization.slug

    # A draft equal to the live site is no draft.
    %{"settings" => %{"lock_version" => lock}} =
      ctx
      |> owner_conn()
      |> put(ctx.admin, %{
        lock_version: settings["lock_version"],
        template: "tiles",
        palette: "palee",
        appearance: "auto",
        calm_motion: false,
        hidden_sections: []
      })
      |> json_response(200)
      |> tap(&assert(&1["settings"]["draft"] == nil))

    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: lock, template: "stories"})
    |> json_response(200)

    assert %{"settings" => %{"draft" => nil, "template" => "tiles"}} =
             ctx |> owner_conn() |> delete("#{ctx.admin}/draft") |> json_response(200)

    # Publishing without a draft still answers the settings.
    assert %{"settings" => %{"draft" => nil, "published_at" => published_at}} =
             ctx |> owner_conn() |> post("#{ctx.admin}/publish") |> json_response(200)

    assert is_binary(published_at)

    # Unknown keys are field errors; members cannot publish.
    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: 0, palette: "rainbow"})
    |> json_response(422)

    build_conn() |> put_bearer_token(ctx.member) |> post("#{ctx.admin}/publish") |> response(403)
    build_conn() |> put_bearer_token(ctx.member) |> get("#{ctx.admin}/preview") |> response(403)
  end

  test "publish puts the draft live", ctx do
    publish_page!(ctx)

    %{"settings" => %{"lock_version" => _lock}} =
      ctx
      |> owner_conn()
      |> put(ctx.admin, %{lock_version: 0, template: "stories", palette: "navy"})
      |> json_response(200)

    assert %{"settings" => %{"template" => "stories", "palette" => "navy", "draft" => nil}} =
             ctx |> owner_conn() |> post("#{ctx.admin}/publish") |> json_response(200)

    assert %{"template" => "stories", "palette" => "navy"} =
             build_conn() |> get(ctx.public) |> json_response(200)
  end

  test "the preview works before the public page is published", ctx do
    build_conn() |> get(ctx.public) |> json_response(404)

    assert %{"slug" => slug, "template" => "tiles", "photos" => %{"items" => []}} =
             ctx |> owner_conn() |> get("#{ctx.admin}/preview?lang=en") |> json_response(200)

    assert slug == ctx.organization.slug
  end

  test "a moved site: the notice shows until dismissed and staff hear once", ctx do
    {:ok, _settings} = BoxSite.update_settings(ctx.context, %{"forms_enabled" => true}, nil)

    in_box(ctx, fn ->
      Repo.query!(
        "UPDATE box_site_settings SET template = 'arena', template_notice = true WHERE organization_id = $1",
        [Ecto.UUID.dump!(ctx.organization.id)]
      )
    end)

    assert %{"settings" => %{"template" => "arena", "template_notice" => true}} =
             ctx |> owner_conn() |> get(ctx.admin) |> json_response(200)

    now = DateTime.utc_now()
    assert SiteTemplateNotice.notify(%{organization_id: ctx.organization.id}, now)
    refute SiteTemplateNotice.notify(%{organization_id: ctx.organization.id}, now)

    notices =
      in_box(ctx, fn ->
        Repo.query!(
          "SELECT user_id FROM notifications WHERE type = 'site_template_changed' AND organization_id = $1",
          [Ecto.UUID.dump!(ctx.organization.id)]
        )
      end)

    assert notices.rows == [[Ecto.UUID.dump!(ctx.owner.id)]]

    assert %{"settings" => %{"template_notice" => false, "template" => "arena"}} =
             ctx |> owner_conn() |> delete("#{ctx.admin}/notice") |> json_response(200)
  end

  test "photos: the page's cover and photos first, then public room photos, at most 12", ctx do
    ids = for _ <- 1..13, do: upload!(ctx.context)
    [cover | photos] = ids
    publish_page!(ctx, %{"cover_photo_id" => cover, "photo_ids" => photos})

    site = build_conn() |> get(ctx.public) |> json_response(200)

    assert "photos" in site["sections"]
    items = site["photos"]["items"]
    assert length(items) == 12
    assert Enum.map(items, & &1["id"]) == Enum.take(ids, 12)

    assert %{"url" => url, "width" => 40, "height" => 30, "caption" => nil} = hd(items)
    assert is_binary(url)

    # Switched off, the section and its items go.
    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: 0, hidden_sections: ["photos"]})
    |> json_response(200)

    ctx |> owner_conn() |> post("#{ctx.admin}/publish") |> json_response(200)
    site = build_conn() |> get(ctx.public) |> json_response(200)
    refute "photos" in site["sections"]
    assert site["photos"] == %{"items" => [], "video" => nil}
  end

  test "community numbers: classes this week and PRs this year, aggregates only", ctx do
    publish_page!(ctx)
    workout = workout_fixture(ctx.owner, %{tenant_context: ctx.context})
    slot_fixture(workout, %{tenant_context: ctx.context})
    slot_fixture(workout, %{tenant_context: ctx.context, scheduled_at: in_hours(30)})

    for name <- ["Back squat", "Deadlift"] do
      {:ok, _pr} =
        CreatePR.call(UserContext.new(ctx.member), %{
          "name" => name,
          "current_score" => 100,
          "unit" => "kg",
          "beaten_on" => Date.to_iso8601(Date.utc_today()),
          "organization_slug" => ctx.organization.slug
        })
    end

    site = build_conn() |> get(ctx.public) |> json_response(200)

    assert "stats" in site["sections"]

    assert site["stats"] == %{
             "classes_per_week" => 2,
             "prs_this_year" => 2,
             "years_open" => nil
           }

    refute inspect(site["stats"]) =~ ctx.member.id
  end

  defp in_box(ctx, fun), do: RepoContext.run(ctx.context, fun)

  defp in_hours(hours),
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(hours * 3600, :second)
end
