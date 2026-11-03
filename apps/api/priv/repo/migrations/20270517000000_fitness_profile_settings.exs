defmodule Palee.Repo.Migrations.FitnessProfileSettings do
  @moduledoc """
  ADR-395: «Επίπεδο φυσικής κατάστασης» version 2.

    * `fitness_profile_settings` (account level, one row per person): the
      body weight the lifts are read against, the birth year for the age
      bands and what the card shows (`all`, `progress_only`, `none`). Only
      its owner reads or writes it under forced RLS.
    * `fitness_display_overrides` (per box): what a client's coach chose the
      card shows for that client (`progress_only` or `none`). The box's staff
      read and write it in the box's scope; the client reads their own rows
      in every box (a second, SELECT-only policy).
    * `palee_coach_client_fitness_settings(p_client)`: a narrow SECURITY
      DEFINER function (ADR-131 §2) that returns the client's weight, birth
      year and choice only to a coach with an active coaching relationship
      with them in the caller's box (ANR 2026-11-03: «personal trainer/coach
      (if assigned/exists) can see them»). It pins only `search_path`.
  """

  use Ecto.Migration

  def up do
    create table(:fitness_profile_settings, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :body_weight_kg, :decimal, precision: 5, scale: 1
      add :birth_year, :integer
      add :display, :string, size: 16, null: false, default: "all"

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:fitness_profile_settings, :fitness_profile_settings_display_check,
             check: "display IN ('all', 'progress_only', 'none')"
           )

    create constraint(:fitness_profile_settings, :fitness_profile_settings_weight_check,
             check: "body_weight_kg IS NULL OR (body_weight_kg >= 25 AND body_weight_kg <= 300)"
           )

    create constraint(:fitness_profile_settings, :fitness_profile_settings_birth_year_check,
             check: "birth_year IS NULL OR (birth_year >= 1900 AND birth_year <= 2100)"
           )

    owner = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY fitness_profile_settings_owner_policy ON fitness_profile_settings
    FOR ALL USING (#{owner}) WITH CHECK (#{owner})
    """)

    execute("ALTER TABLE fitness_profile_settings ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE fitness_profile_settings FORCE ROW LEVEL SECURITY")

    create table(:fitness_display_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :client_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :display, :string, size: 16, null: false
      add :set_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fitness_display_overrides, [:organization_id, :client_user_id])
    create index(:fitness_display_overrides, [:client_user_id])

    create constraint(:fitness_display_overrides, :fitness_display_overrides_display_check,
             check: "display IN ('progress_only', 'none')"
           )

    tenant = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"
    client = "client_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY fitness_display_overrides_tenant_policy ON fitness_display_overrides
    FOR ALL USING (#{tenant}) WITH CHECK (#{tenant})
    """)

    execute("""
    CREATE POLICY fitness_display_overrides_client_read_policy ON fitness_display_overrides
    FOR SELECT USING (#{client})
    """)

    execute("ALTER TABLE fitness_display_overrides ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE fitness_display_overrides FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE FUNCTION palee_coach_client_fitness_settings(p_client uuid)
    RETURNS TABLE (body_weight_kg numeric, birth_year integer, display text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT s.body_weight_kg, s.birth_year, s.display::text
      FROM fitness_profile_settings s
      WHERE s.user_id = p_client
        AND EXISTS (
          SELECT 1
          FROM coaching_relationships r
          WHERE r.client_user_id = p_client
            AND r.coach_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
            AND r.organization_id =
                  NULLIF(current_setting('app.organization_id', true), '')::uuid
            AND r.ended_at IS NULL
        )
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_coach_client_fitness_settings(uuid)")
    drop table(:fitness_display_overrides)
    drop table(:fitness_profile_settings)
  end
end
