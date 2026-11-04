defmodule Palee.Scheduling.ClassTypeLevelsSyncTest do
  @moduledoc """
  ADR-490 rollout: until TD-490 drops `class_types.level`, the
  `class_types_sync_levels` trigger keeps it and `levels` in step, so pods of
  the previous release (which write only `level`) and new pods agree.
  """

  use Palee.DataCase, async: false

  alias Palee.{AnalyticsHelpers, Repo, Scheduling}

  setup do
    {_organization, _owner, context} = AnalyticsHelpers.organization_fixture()

    {:ok, type} =
      Scheduling.create_class_type(context, %{
        name: "Foundations",
        slug: "foundations",
        sort_order: 0
      })

    %{type: type, context: context}
  end

  defp row(id) do
    %{rows: [[level, levels]]} =
      Repo.query!("SELECT level, levels FROM class_types WHERE id = $1", [Ecto.UUID.dump!(id)])

    {level, levels}
  end

  defp old_pod_sets_level(id, level),
    do:
      Repo.query!("UPDATE class_types SET level = $2 WHERE id = $1", [Ecto.UUID.dump!(id), level])

  test "an old pod's level reaches levels", %{type: type} do
    old_pod_sets_level(type.id, "beginner")
    assert row(type.id) == {"beginner", ["beginner"]}

    old_pod_sets_level(type.id, "all_levels")
    assert row(type.id) == {"all_levels", []}
  end

  test "an old pod's insert with a level fills levels", %{type: type} do
    %{rows: [[org_id]]} =
      Repo.query!("SELECT organization_id FROM class_types WHERE id = $1", [
        Ecto.UUID.dump!(type.id)
      ])

    %{rows: [[id]]} =
      Repo.query!(
        """
        INSERT INTO class_types (id, organization_id, name, slug, sort_order, level, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, 'Comp', 'comp', 9, 'advanced', now(), now()) RETURNING id
        """,
        [org_id]
      )

    assert row(Ecto.UUID.load!(id)) == {"advanced", ["advanced"]}
  end

  test "a new pod's levels reach the old single level", %{type: type, context: context} do
    {:ok, _} =
      Scheduling.update_class_type(context, type.id, %{
        name: type.name,
        sort_order: type.sort_order,
        levels: ["advanced"]
      })

    assert row(type.id) == {"advanced", ["advanced"]}

    {:ok, _} =
      Scheduling.update_class_type(context, type.id, %{
        name: type.name,
        sort_order: type.sort_order,
        levels: ["beginner", "intermediate"]
      })

    assert row(type.id) == {"all_levels", ["beginner", "intermediate"]}

    {:ok, _} =
      Scheduling.update_class_type(context, type.id, %{
        name: type.name,
        sort_order: type.sort_order,
        levels: ["intermediate"]
      })

    assert row(type.id) == {"all_levels", ["intermediate"]}
  end
end
