defmodule Palee.Repo.Migrations.ReviewAsks do
  @moduledoc """
  ADR-355: asking members for a Google review at a good moment.

    * `review_ask_settings` – one row per box: the Google Place ID, on/off
      and the attendance milestones;
    * `review_asks` – one row per ask shown to a member and what they did;
    * `review_ask_opt_outs` – members who asked never to be asked again.
  """

  use Ecto.Migration

  @tables ~w(review_ask_settings review_asks review_ask_opt_outs)

  def up do
    create table(:review_ask_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :google_place_id, :string, size: 300
      add :enabled, :boolean, null: false, default: false
      add :milestones, {:array, :integer}, null: false, default: [10, 50, 100]
      add :lock_version, :integer, null: false, default: 1
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:review_ask_settings, [:organization_id])

    create constraint(:review_ask_settings, :review_ask_settings_check,
             check: """
             (google_place_id IS NULL OR (google_place_id ~ '^[A-Za-z0-9_-]+$' AND char_length(google_place_id) BETWEEN 10 AND 300))
             AND (NOT enabled OR google_place_id IS NOT NULL)
             AND cardinality(milestones) BETWEEN 1 AND 6
             """
           )

    create table(:review_asks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :trigger, :string, null: false
      add :milestone, :integer, null: false
      add :status, :string, null: false, default: "shown"
      add :shown_at, :utc_datetime_usec, null: false
      add :responded_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:review_asks, [:organization_id, :user_id, :trigger, :milestone])
    create index(:review_asks, [:organization_id, :shown_at])

    create constraint(:review_asks, :review_asks_check,
             check: """
             trigger IN ('attendance_milestone')
             AND status IN ('shown', 'opened', 'later', 'dismissed')
             AND milestone > 0
             AND (status = 'shown' OR responded_at IS NOT NULL)
             """
           )

    create table(:review_ask_opt_outs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :opted_out_at, :utc_datetime_usec, null: false
    end

    create unique_index(:review_ask_opt_outs, [:organization_id, :user_id])

    for table <- @tables do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  def down do
    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
  end
end
