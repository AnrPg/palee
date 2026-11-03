defmodule Palee.Repo.Migrations.BoxReviewReports do
  @moduledoc """
  ADR-397 (Palee v3.2): «Αναφορά» on the in-app reviews of a box (ADR-386),
  decided only by the Palee team.

    * `box_reviews.moderation` (`hidden` | `removed`) and `moderated_at`: what
      the Palee team decided. A hidden review keeps its text and can be shown
      again; a removed one loses its text and the box's reply. Neither shows
      nor counts in the average; only the author still sees theirs, with the
      statement of reasons.
    * `box_review_reports`: who reported which review, as a member or as the
      box, why (a fixed reason, an optional note), what the review said then
      (so an edit cannot hide the evidence) and how it ended. One open report
      per person and review.
    * `box_review_decisions`: one row per decision of the Palee team on a
      review, the statement of reasons the author receives (DSA Art. 17):
      outcome, ground, text, who decided and when, how many reports it closed.

  Both new tables are tenant tables (forced RLS and the tenant trigger) with a
  second, read-only policy for the Palee team (`palee_acting_user_is_vendor()`),
  whose queue spans every box; the decision itself is written in the box's
  own tenant session. `palee_forget_box_review_reports(uuid)` deletes a
  person's reports when their profile is kept anonymised (a deleted user row
  takes them by cascade). Notification types `box_review_moderated` (to the
  author) and `box_review_report_decided` (to whoever reported).
  Functions pin only `search_path`.
  """

  use Ecto.Migration

  @tables ~w(box_review_reports box_review_decisions)
  @types ~w(box_review_moderated box_review_report_decided)
  @reasons "'offensive', 'personal_data', 'not_genuine', 'spam', 'illegal', 'other'"

  def up do
    alter table(:box_reviews) do
      add :moderation, :text
      add :moderated_at, :utc_datetime_usec
    end

    create constraint(:box_reviews, :box_reviews_moderation_check,
             check: """
             (moderation IS NULL OR moderation IN ('hidden', 'removed'))
             AND ((moderation IS NULL) = (moderated_at IS NULL))
             AND (moderation IS DISTINCT FROM 'removed' OR (body IS NULL AND reply_body IS NULL))
             """
           )

    create table(:box_review_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :review_id, references(:box_reviews, type: :binary_id, on_delete: :nilify_all)

      add :review_author_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :outcome, :text, null: false
      add :ground, :text, null: false
      add :statement, :text
      add :reports_count, :integer, null: false, default: 0
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:box_review_decisions, [:organization_id, :review_id])
    create index(:box_review_decisions, [:review_author_id])
    create index(:box_review_decisions, [:decided_at])

    create constraint(:box_review_decisions, :box_review_decisions_check,
             check: """
             outcome IN ('keep', 'hide', 'remove')
             AND ground IN ('no_violation', #{@reasons})
             AND ((outcome = 'keep') = (ground = 'no_violation'))
             AND (statement IS NULL OR char_length(statement) BETWEEN 1 AND 1000)
             AND (outcome = 'keep' OR statement IS NOT NULL)
             AND reports_count >= 0
             """
           )

    create table(:box_review_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :review_id, references(:box_reviews, type: :binary_id, on_delete: :delete_all),
        null: false

      add :review_author_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :reporter_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :reporter_role, :text, null: false
      add :reason, :text, null: false
      add :note, :text
      add :review_rating, :integer, null: false
      add :review_body, :text
      add :status, :text, null: false, default: "open"

      add :decision_id,
          references(:box_review_decisions, type: :binary_id, on_delete: :nilify_all)

      add :decided_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:box_review_reports, [:review_id, :reporter_id],
             where: "status = 'open'",
             name: :box_review_reports_open_pair_index
           )

    create index(:box_review_reports, [:status, :inserted_at])
    create index(:box_review_reports, [:organization_id, :reporter_id, :inserted_at])
    create index(:box_review_reports, [:review_author_id])

    create constraint(:box_review_reports, :box_review_reports_check,
             check: """
             reporter_id <> review_author_id
             AND reporter_role IN ('member', 'box')
             AND reason IN (#{@reasons})
             AND (note IS NULL OR char_length(note) BETWEEN 1 AND 500)
             AND review_rating BETWEEN 1 AND 5
             AND (review_body IS NULL OR char_length(review_body) BETWEEN 1 AND 2000)
             AND status IN ('open', 'kept', 'hidden', 'removed')
             AND ((status = 'open') = (decided_at IS NULL))
             """
           )

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

      # The Palee team's queue spans every box; it only reads here.
      execute("""
      CREATE POLICY #{table}_vendor_read ON #{table}
      FOR SELECT USING (palee_acting_user_is_vendor())
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    # Account deletion of a profile kept anonymised (ADR-211): the person's
    # reports go; decisions about their review stay with the review.
    execute("""
    CREATE FUNCTION palee_forget_box_review_reports(person uuid)
    RETURNS integer
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      deleted integer;
    BEGIN
      DELETE FROM public.box_review_reports WHERE reporter_id = person;
      GET DIAGNOSTICS deleted = ROW_COUNT;
      RETURN deleted;
    END
    $$
    """)

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN ('box_review_moderated', 'box_review_report_decided')")
    rewrite_notification_types(&(&1 -- @types))
    execute("DROP FUNCTION IF EXISTS palee_forget_box_review_reports(uuid)")

    drop table(:box_review_reports)
    drop table(:box_review_decisions)

    drop constraint(:box_reviews, :box_reviews_moderation_check)

    alter table(:box_reviews) do
      remove :moderated_at
      remove :moderation
    end
  end

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
