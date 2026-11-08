defmodule Palee.Repo.Migrations.PackageAudience do
  @moduledoc """
  ADR-553: who sees a box's subscription packages, on its Palee page and its
  website alike.

    * `finance_settings.package_audience`: the box's choice (`all`, `own`,
      `none`);
    * `membership_packages.audience`: a package's own choice, NULL follows
      the box;
    * `finance_package_audience_exceptions`: people the box always shows
      (`show`) or never shows (`hide`) one package, or every package when
      `membership_package_id` is NULL. One row per person and package.

  The website's «Πακέτα» switch becomes this same setting: a box whose
  website hid its packages gets `none`, and the website no longer keeps the
  section among its hidden ones.
  """

  use Ecto.Migration

  def up do
    alter table(:finance_settings) do
      add :package_audience, :string, null: false, default: "all"
    end

    create constraint(:finance_settings, :finance_settings_package_audience_check,
             check: "package_audience IN ('all', 'own', 'none')"
           )

    alter table(:membership_packages) do
      add :audience, :string
    end

    create constraint(:membership_packages, :membership_packages_audience_check,
             check: "audience IS NULL OR audience IN ('all', 'own', 'none')"
           )

    create table(:finance_package_audience_exceptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_package_id,
          references(:membership_packages, type: :binary_id, on_delete: :delete_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :effect, :string, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(
             :finance_package_audience_exceptions,
             :finance_package_audience_exceptions_effect_check,
             check: "effect IN ('show', 'hide')"
           )

    create unique_index(
             :finance_package_audience_exceptions,
             [:organization_id, :membership_package_id, :user_id],
             name: :finance_package_audience_exceptions_one_per_person_index,
             nulls_distinct: false
           )

    create index(:finance_package_audience_exceptions, [:user_id])

    execute("""
    CREATE TRIGGER finance_package_audience_exceptions_apply_tenant_context
    BEFORE INSERT OR UPDATE ON finance_package_audience_exceptions
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    org = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"

    execute("""
    CREATE POLICY finance_package_audience_exceptions_tenant_policy
    ON finance_package_audience_exceptions
    FOR ALL USING (#{org}) WITH CHECK (#{org})
    """)

    execute("ALTER TABLE finance_package_audience_exceptions ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_package_audience_exceptions FORCE ROW LEVEL SECURITY")

    # The website's «Πακέτα» switch was off: nobody sees the packages now.
    execute("""
    UPDATE finance_settings f SET package_audience = 'none', updated_at = now()
    FROM box_site_settings s
    WHERE s.organization_id = f.organization_id AND 'packages' = ANY(s.hidden_sections)
    """)

    execute("""
    INSERT INTO finance_settings (id, organization_id, package_audience, inserted_at, updated_at)
    SELECT gen_random_uuid(), s.organization_id, 'none', now(), now()
    FROM box_site_settings s
    WHERE 'packages' = ANY(s.hidden_sections)
      AND NOT EXISTS (SELECT 1 FROM finance_settings f WHERE f.organization_id = s.organization_id)
    """)

    execute("""
    UPDATE box_site_settings
    SET hidden_sections = array_remove(hidden_sections, 'packages')
    WHERE 'packages' = ANY(hidden_sections)
    """)

    execute("""
    UPDATE box_site_settings
    SET draft = jsonb_set(draft, '{hidden_sections}',
      COALESCE((SELECT jsonb_agg(v) FROM jsonb_array_elements(draft->'hidden_sections') v
                WHERE v <> '"packages"'::jsonb), '[]'::jsonb))
    WHERE draft IS NOT NULL AND jsonb_typeof(draft->'hidden_sections') = 'array'
      AND draft->'hidden_sections' @> '["packages"]'::jsonb
    """)
  end

  def down do
    drop table(:finance_package_audience_exceptions)
    drop constraint(:membership_packages, :membership_packages_audience_check)

    alter table(:membership_packages) do
      remove :audience
    end

    drop constraint(:finance_settings, :finance_settings_package_audience_check)

    alter table(:finance_settings) do
      remove :package_audience
    end
  end
end
