defmodule Palee.Repo.Migrations.BoxReviewsAndSiteV31 do
  @moduledoc """
  ADR-386..388 (Palee v3.1, W4 build):

    * `box_reviews` – in-app reviews of a box (stars and text) by people who
      checked in there, one per person, with the box's reply (ADR-386);
    * `google_place_snapshots` – the box's Google rating and up to five
      reviews, refreshed daily from the Places API (ADR-387);
    * `box_site_settings` – the «WOD της ημέρας» switch and the optional
      English text of the box's about (ADR-388);
    * `review_ask_settings` – asks no longer need a Google Place ID: the card
      also offers the in-app review (ADR-386);
    * notification type `site_request` – a trial request or question from the
      website reached «Ενδιαφερόμενοι» (ADR-388).
  """

  use Ecto.Migration

  @tables ~w(box_reviews google_place_snapshots)
  @types ~w(site_request)

  def up do
    alter table(:box_site_settings) do
      add :public_wod, :boolean, null: false, default: false
      add :about_en, :text
    end

    create constraint(:box_site_settings, :box_site_settings_about_en_check,
             check: "about_en IS NULL OR char_length(about_en) <= 4000"
           )

    execute("ALTER TABLE review_ask_settings DROP CONSTRAINT review_ask_settings_check")

    create constraint(:review_ask_settings, :review_ask_settings_check,
             check: """
             (google_place_id IS NULL OR (google_place_id ~ '^[A-Za-z0-9_-]+$' AND char_length(google_place_id) BETWEEN 10 AND 300))
             AND cardinality(milestones) BETWEEN 1 AND 6
             """
           )

    create table(:box_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :rating, :integer, null: false
      add :body, :text
      add :locale, :string, size: 10
      add :edited_at, :utc_datetime_usec
      add :reply_body, :text
      add :replied_at, :utc_datetime_usec
      add :replied_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:box_reviews, [:organization_id, :user_id])
    create index(:box_reviews, [:organization_id, :inserted_at])

    create constraint(:box_reviews, :box_reviews_check,
             check: """
             rating BETWEEN 1 AND 5
             AND (body IS NULL OR char_length(body) BETWEEN 1 AND 2000)
             AND (reply_body IS NULL OR char_length(reply_body) BETWEEN 1 AND 2000)
             AND ((reply_body IS NULL) = (replied_at IS NULL))
             """
           )

    create table(:google_place_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :place_id, :string, size: 300, null: false
      add :name, :string, size: 200
      add :rating, :decimal, precision: 2, scale: 1
      add :rating_count, :integer
      add :maps_uri, :string, size: 500
      add :reviews, {:array, :map}, null: false, default: []
      add :status, :string, null: false, default: "ok"
      add :fetched_at, :utc_datetime_usec, null: false
      add :next_refresh_at, :utc_datetime_usec, null: false
      add :attempts, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:google_place_snapshots, [:organization_id])

    create constraint(:google_place_snapshots, :google_place_snapshots_check,
             check: """
             status IN ('ok', 'not_found', 'failed')
             AND (rating IS NULL OR rating BETWEEN 1 AND 5)
             AND (rating_count IS NULL OR rating_count >= 0)
             AND cardinality(reviews) <= 5
             AND attempts >= 0
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

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    # Workers: the boxes whose Google listing is due a refresh (ADR-387):
    # a Place ID with no snapshot, a snapshot of another place, or one due.
    execute("""
    CREATE FUNCTION palee_google_place_due_organizations(due_at timestamptz)
    RETURNS TABLE (organization_id uuid)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT s.organization_id FROM public.review_ask_settings s
      JOIN public.organizations o ON o.id = s.organization_id
      LEFT JOIN public.google_place_snapshots g ON g.organization_id = s.organization_id
      WHERE s.google_place_id IS NOT NULL AND o.status = 'active'
        AND (g.id IS NULL OR g.place_id <> s.google_place_id OR g.next_refresh_at <= due_at)
      LIMIT 500
    $$
    """)

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN ('site_request')")
    rewrite_notification_types(&(&1 -- @types))
    execute("DROP FUNCTION IF EXISTS palee_google_place_due_organizations(timestamptz)")

    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))

    execute("ALTER TABLE review_ask_settings DROP CONSTRAINT review_ask_settings_check")

    create constraint(:review_ask_settings, :review_ask_settings_check,
             check: """
             (google_place_id IS NULL OR (google_place_id ~ '^[A-Za-z0-9_-]+$' AND char_length(google_place_id) BETWEEN 10 AND 300))
             AND (NOT enabled OR google_place_id IS NOT NULL)
             AND cardinality(milestones) BETWEEN 1 AND 6
             """
           )

    drop constraint(:box_site_settings, :box_site_settings_about_en_check)

    alter table(:box_site_settings) do
      remove :about_en
      remove :public_wod
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
