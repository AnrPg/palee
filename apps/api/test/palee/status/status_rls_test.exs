defmodule Palee.Status.StatusRLSTest do
  @moduledoc """
  ADR-364 under real row-level security (the runtime role): anyone reads the
  public status tables, a system session (no acting user) and vendors
  write them, a signed-in member can neither write them nor read
  subscribers.
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.{Organizations, RLSCase, Status}
  alias Palee.Infrastructure.Tenancy.RepoContext

  setup do
    RLSCase.ensure_runtime_role!()
    vendor = user_fixture()
    {:ok, _} = Organizations.grant_vendor(vendor.id)
    {:ok, platform} = Organizations.resolve_platform_context(vendor)
    %{platform: platform, member: user_fixture()}
  end

  test "public reads, system and vendor writes, member writes refused", ctx do
    Repo.query!("SET LOCAL ROLE #{RLSCase.runtime_role()}")
    now = DateTime.utc_now()

    assert :ok =
             Status.record_probe([%{component: "app", status: "operational", reason: nil}], now)

    assert {:ok, _incident, _update} =
             Status.create_incident(ctx.platform, %{title: "Slow", body: "Looking"}, now)

    {:ok, {:confirm, _}} = Status.request_subscription("a@b.gr", "en", "token-1", now)

    # A member's session: the page reads fine, writes and subscribers do not.
    RepoContext.run(%{user_id: ctx.member.id}, fn ->
      assert %{status: _, active: [_]} = Status.overview(now)
      assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM status_subscribers")
    end)

    assert_raise Postgrex.Error, ~r/row-level security/, fn ->
      RepoContext.run(%{user_id: ctx.member.id}, fn ->
        Repo.query!(
          "INSERT INTO status_incidents (id, kind, title, impact, status, started_at, inserted_at, updated_at) " <>
            "VALUES (gen_random_uuid(), 'incident', 'Fake', 'critical', 'investigating', now(), now(), now())"
        )
      end)
    end
  end
end
