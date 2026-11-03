defmodule PaleeWeb.DiplomaSignatureControllerTest do
  @moduledoc """
  ADR-377 amendment (option Γ): a coach's own diploma signature. Only its
  owner reads, replaces or removes it; diplomas keep the one current at the
  award, show the box logo, and lose the signature once it is removed.
  ConnCase: real RLS.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.DiplomaSignatures
  alias Palee.Organizations
  alias Palee.Organizations.Domain.BrandLogoPolicy
  alias Palee.Ranks.SignatureStore
  alias Palee.TestSupport.{MemoryObjectStore, PngFixture}

  setup do
    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)
    slug = Organizations.legacy_organization_slug()

    %{
      owner: owner,
      member: member,
      slug: slug,
      admin: "/api/org/#{slug}/admin",
      staff: "/api/org/#{slug}/staff",
      me: "/api/org/#{slug}/me"
    }
  end

  test "the owner sets, previews, replaces and removes it; diplomas keep the award's",
       %{conn: conn} = ctx do
    assert %{"eligible" => true, "signature" => nil, "limits" => %{"max_bytes" => 524_288}} =
             conn |> as(ctx.owner) |> get("/api/me/diploma-signature") |> json_response(200)

    first = PngFixture.png(300, 100)
    assert %{"signature" => %{"id" => first_id, "width" => 300}} = upload(conn, ctx.owner, first)

    preview = conn |> as(ctx.owner) |> get("/api/me/diploma-signature/image")
    assert response(preview, 200) == first
    assert ["image/png" <> _] = get_resp_header(preview, "content-type")
    assert ["private, no-store"] = get_resp_header(preview, "cache-control")

    [stored] = SignatureStore.list(%{user_id: ctx.owner.id}, ctx.owner.id)
    assert stored.object_key == "users/#{ctx.owner.id}/diploma-signature/#{first_id}.png"
    assert {:ok, ^first} = MemoryObjectStore.get(:media_private, stored.object_key)

    # A promotion made now keeps this signature.
    ladder_id = ladder(conn, ctx)
    first_award = award(conn, ctx, ladder_id, 0)
    assert certificate(conn, ctx, first_award) =~ "/Width 300"

    # Replacing (sent as a data URL): new diplomas get the new one, the issued one keeps the old.
    second = PngFixture.png(400, 100, color: :grey_alpha)

    assert %{"signature" => %{"id" => second_id}} =
             upload(conn, ctx.owner, "data:image/png;base64," <> Base.encode64(second), raw: true)

    assert second_id != first_id
    second_award = award(conn, ctx, ladder_id, 1)
    assert certificate(conn, ctx, second_award) =~ "/Width 400"
    assert certificate(conn, ctx, first_award) =~ "/Width 300"

    assert ["set", "set"] =
             %{user_id: ctx.owner.id}
             |> SignatureStore.events(ctx.owner.id)
             |> Enum.map(& &1.action)

    # Removing: every version goes; diplomas show the empty line.
    assert conn |> as(ctx.owner) |> delete("/api/me/diploma-signature") |> response(204)
    assert SignatureStore.list(%{user_id: ctx.owner.id}, ctx.owner.id) == []
    assert MemoryObjectStore.get(:media_private, stored.object_key) == :error
    refute certificate(conn, ctx, first_award) =~ "/Subtype /Image"
    refute certificate(conn, ctx, second_award) =~ "/Subtype /Image"

    assert "removed" ==
             %{user_id: ctx.owner.id}
             |> SignatureStore.events(ctx.owner.id)
             |> hd()
             |> Map.get(:action)

    assert %{"signature" => nil} =
             conn |> as(ctx.owner) |> get("/api/me/diploma-signature") |> json_response(200)

    assert conn |> as(ctx.owner) |> get("/api/me/diploma-signature/image") |> json_response(404)
  end

  test "the box's uploaded logo is drawn at the top", %{conn: conn} = ctx do
    {:ok, context} = Organizations.resolve_tenant_context(ctx.owner, ctx.slug)
    key = BrandLogoPolicy.object_key(context.organization_id, Ecto.UUID.generate(), "image/png")

    :ok =
      MemoryObjectStore.put_object(
        :branding,
        key,
        PngFixture.png(80, 40, color: :rgb),
        "image/png"
      )

    {:ok, _} =
      Organizations.set_organization_logo(context, nil, %{
        object_key: key,
        url: "https://media.test/logo.png"
      })

    award_id = award(conn, ctx, ladder(conn, ctx), 0)
    pdf = certificate(conn, ctx, award_id)
    assert pdf =~ "/Width 80 /Height 40"
    # No signature: only the logo.
    assert length(Regex.scan(~r{/Subtype /Image}, pdf)) == 1
  end

  test "only staff who award ranks keep one, and nobody reads another's", %{conn: conn} = ctx do
    assert %{"eligible" => false, "signature" => nil} =
             conn |> as(ctx.member) |> get("/api/me/diploma-signature") |> json_response(200)

    assert %{"code" => "forbidden"} =
             conn
             |> as(ctx.member)
             |> send_json(:post, "/api/me/diploma-signature", %{
               image_base64: Base.encode64(PngFixture.png(300, 100))
             })
             |> json_response(403)

    upload(conn, ctx.owner, PngFixture.png(300, 100))
    assert conn |> as(ctx.member) |> get("/api/me/diploma-signature/image") |> json_response(404)
    assert conn |> get("/api/me/diploma-signature") |> json_response(401)
  end

  test "unusable images are refused with a reason", %{conn: conn} = ctx do
    for {bytes, code} <- [
          {"not base64 !", "invalid_signature_image"},
          {Base.encode64("GIF89a" <> :binary.copy(<<0>>, 40)), "signature_unsupported_type"},
          {Base.encode64(PngFixture.png(4, 4, interlace: true)), "signature_unsupported_type"},
          {Base.encode64(PngFixture.png(30, 10)), "signature_too_small"},
          {Base.encode64(PngFixture.png(1700, 30, color: :rgb)),
           "signature_dimensions_too_large"},
          {Base.encode64(<<137, 80, 78, 71>> <> :binary.copy(<<0>>, 600_000)),
           "signature_too_large"}
        ] do
      assert %{"code" => ^code} =
               conn
               |> as(ctx.owner)
               |> send_json(:post, "/api/me/diploma-signature", %{image_base64: bytes})
               |> json_response(422)
    end

    assert SignatureStore.list(%{user_id: ctx.owner.id}, ctx.owner.id) == []
  end

  test "account deletion's purge and the data export", %{conn: conn} = ctx do
    image = PngFixture.png(300, 100)
    %{"signature" => %{"id" => id}} = upload(conn, ctx.owner, image)

    assert [{"diploma-signature/" <> name, ^image}] = DiplomaSignatures.export_files(ctx.owner.id)
    assert name == "#{id}.png"

    assert :ok = DiplomaSignatures.purge_person(ctx.owner.id)
    assert SignatureStore.list(%{user_id: ctx.owner.id}, ctx.owner.id) == []
    assert DiplomaSignatures.export_files(ctx.owner.id) == []
    assert DiplomaSignatures.pdf_image(id) == nil
  end

  defp upload(conn, user, bytes, opts \\ []) do
    body = if opts[:raw], do: bytes, else: Base.encode64(bytes)

    conn
    |> as(user)
    |> send_json(:post, "/api/me/diploma-signature", %{image_base64: body})
    |> json_response(200)
  end

  defp ladder(conn, ctx) do
    %{"ladder" => %{"id" => id}} =
      conn
      |> as(ctx.owner)
      |> send_json(:post, "#{ctx.admin}/rank-ladders", %{
        name: "Ζώνες BJJ #{System.unique_integer([:positive])}",
        discipline: "bjj_grappling",
        ranks: [%{name: "Λευκή", color: "white"}, %{name: "Μπλε", color: "blue"}]
      })
      |> json_response(201)

    id
  end

  defp award(conn, ctx, ladder_id, position) do
    %{"ladders" => ladders} =
      conn |> as(ctx.owner) |> get("#{ctx.admin}/rank-ladders") |> json_response(200)

    rank =
      ladders |> Enum.find(&(&1["id"] == ladder_id)) |> Map.fetch!("ranks") |> Enum.at(position)

    %{"award" => %{"id" => id}} =
      conn
      |> as(ctx.owner)
      |> send_json(:post, "#{ctx.staff}/clients/#{ctx.member.id}/ranks", %{
        ladder_id: ladder_id,
        rank_id: rank["id"]
      })
      |> json_response(201)

    id
  end

  defp certificate(conn, ctx, award_id) do
    conn
    |> as(ctx.member)
    |> get("#{ctx.me}/ranks/awards/#{award_id}/certificate")
    |> response(200)
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end
end
