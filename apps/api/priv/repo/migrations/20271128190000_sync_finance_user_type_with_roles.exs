defmodule Palee.Repo.Migrations.SyncFinanceUserTypeWithRoles do
  @moduledoc """
  ADR-812: a finance profile is held as the role the person buys as in the
  box, worked out from their box roles (`athlete`, then `member`, then
  `guest`). Until now `memberships.user_type_snapshot` was written once, when
  the profile was created, and never followed a role change. This heals the
  profiles that went stale; from now on every role change keeps it in step.
  A profile whose person holds no buyer role keeps its last value.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE memberships AS m
    SET user_type_snapshot = CASE
          WHEN 'athlete' = ANY(om.roles::text[]) THEN 'athlete'
          WHEN 'member' = ANY(om.roles::text[]) THEN 'member'
          ELSE 'guest'
        END,
        updated_at = now()
    FROM organization_memberships AS om
    WHERE om.organization_id = m.organization_id
      AND om.user_id = m.user_id
      AND om.roles::text[] && ARRAY['athlete', 'member', 'guest']
      AND m.user_type_snapshot IS DISTINCT FROM CASE
          WHEN 'athlete' = ANY(om.roles::text[]) THEN 'athlete'
          WHEN 'member' = ANY(om.roles::text[]) THEN 'member'
          ELSE 'guest'
        END
    """)
  end

  # The stale values are not worth restoring.
  def down, do: :ok
end
