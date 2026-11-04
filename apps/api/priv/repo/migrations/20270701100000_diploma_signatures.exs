defmodule Palee.Repo.Migrations.DiplomaSignatures do
  @moduledoc """
  ADR-377 addendum (option Γ): the diploma carries the box logo and the
  awarding coach's signature.

    * `diploma_signatures` – a coach's signature image («Υπογραφή για
      διπλώματα»), stored privately under the person's own storage prefix.
      One current row per person (`retired_at` empty); replacing it retires
      the old row, which issued diplomas keep pointing at. Removing it
      deletes every row and object of the person.
    * `diploma_signature_events` – the person's own audit trail: when a
      signature was set or removed (insert-only for the person).
    * `rank_awards.signature_id` – the signature current when the award was
      made (a snapshot reference, no foreign key: the row lives outside the
      box and may be removed).

  Row security: the person (`app.user_id`) and system sessions (no acting
  person, which is how a diploma is drawn) only.
  """

  use Ecto.Migration

  @me "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @own_or_system "(user_id = #{@me} OR #{@me} IS NULL)"

  def up do
    create table(:diploma_signatures, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :object_key, :string, size: 255, null: false
      add :content_type, :string, size: 32, null: false
      add :byte_size, :integer, null: false
      add :width, :integer, null: false
      add :height, :integer, null: false
      add :sha256, :string, size: 64, null: false
      add :retired_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:diploma_signatures, [:user_id],
             where: "retired_at IS NULL",
             name: :diploma_signatures_current_index
           )

    create index(:diploma_signatures, [:user_id])

    create constraint(:diploma_signatures, :diploma_signatures_check,
             check:
               "content_type IN ('image/png', 'image/jpeg') AND byte_size > 0 AND width > 0 AND height > 0"
           )

    execute("""
    CREATE POLICY diploma_signatures_owner_policy ON diploma_signatures
    USING #{@own_or_system} WITH CHECK #{@own_or_system}
    """)

    secure(:diploma_signatures)

    create table(:diploma_signature_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :action, :string, size: 16, null: false
      add :signature_id, :binary_id
      add :sha256, :string, size: 64
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:diploma_signature_events, [:user_id, :occurred_at])

    create constraint(:diploma_signature_events, :diploma_signature_events_action_check,
             check: "action IN ('set', 'removed')"
           )

    execute("""
    CREATE POLICY diploma_signature_events_read_policy ON diploma_signature_events
    FOR SELECT USING #{@own_or_system}
    """)

    execute("""
    CREATE POLICY diploma_signature_events_insert_policy ON diploma_signature_events
    FOR INSERT WITH CHECK #{@own_or_system}
    """)

    secure(:diploma_signature_events)

    alter table(:rank_awards) do
      add :signature_id, :binary_id
    end
  end

  def down do
    alter table(:rank_awards) do
      remove :signature_id
    end

    drop table(:diploma_signature_events)
    drop table(:diploma_signatures)
  end

  defp secure(table) do
    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end
end
