defmodule Palee.Repo.Migrations.PurchaseAdmission do
  @moduledoc """
  ADR-642: buying a package makes a person a box member when the purchase is
  real, not when they open the buy dialog (ANR 2026-11-13, «Με ενεργό
  πακέτο»).

    * `organization_memberships.purchase_admission_at`: the person came in
      through a package of the box (ADR-552) and has no package yet. While
      they only started buying they are a guest of the box (role `guest`);
      sending «Το θέλω» makes them a member on these terms (their one class
      while waiting, ADR-633); a package that starts clears it. A request
      that closes with no package makes them a guest again.

  Carried over: members who came in by starting to buy (a «Το θέλω» or an
  online payment for a package within ten minutes of joining, from
  2026-11-06 when ADR-552 shipped) and who have no Finance profile, no
  request still waiting, no invitation and no accepted join request become
  guests on these terms.
  """

  use Ecto.Migration

  def up do
    alter table(:organization_memberships) do
      add :purchase_admission_at, :utc_datetime_usec
    end

    execute(carry_over_sql())
  end

  @doc "The carry-over, on its own so a test can run it on rows it made."
  def carry_over_sql do
    """
    UPDATE organization_memberships AS om
    SET roles = ARRAY['guest']::varchar[], role = 'guest', purchase_admission_at = om.joined_at,
        updated_at = now()
    WHERE om.status = 'active'
      AND om.left_at IS NULL
      AND om.roles::text[] = ARRAY['member']
      AND om.invited_by_user_id IS NULL
      AND om.joined_at >= '2026-11-06T00:00:00Z'
      AND NOT EXISTS (
        SELECT 1 FROM memberships AS fm
        WHERE fm.organization_id = om.organization_id AND fm.user_id = om.user_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM finance_package_requests AS r
        WHERE r.organization_id = om.organization_id AND r.user_id = om.user_id
          AND r.status = 'pending'
      )
      AND NOT EXISTS (
        SELECT 1 FROM registration_invitations AS i
        WHERE i.organization_id = om.organization_id AND i.redeemed_by_user_id = om.user_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM organization_join_requests AS j
        WHERE j.organization_id = om.organization_id AND j.user_id = om.user_id
          AND j.status = 'accepted'
      )
      AND (
        EXISTS (
          SELECT 1 FROM finance_package_requests AS r
          WHERE r.organization_id = om.organization_id AND r.user_id = om.user_id
            AND r.inserted_at BETWEEN om.joined_at AND om.joined_at + interval '10 minutes'
        )
        OR EXISTS (
          SELECT 1 FROM payment_intents AS p
          WHERE p.organization_id = om.organization_id AND p.user_id = om.user_id
            AND p.purpose_type = 'membership_package'
            AND p.inserted_at BETWEEN om.joined_at AND om.joined_at + interval '10 minutes'
        )
      )
    """
  end

  def down do
    execute("""
    UPDATE organization_memberships
    SET roles = ARRAY['member']::varchar[], role = 'member', updated_at = now()
    WHERE purchase_admission_at IS NOT NULL AND roles::text[] = ARRAY['guest']
    """)

    alter table(:organization_memberships) do
      remove :purchase_admission_at
    end
  end
end
