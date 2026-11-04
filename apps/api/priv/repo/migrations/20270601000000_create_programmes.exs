defmodule Palee.Repo.Migrations.CreateProgrammes do
  @moduledoc """
  ADR-370/371: training programmes a box or a coach sells (CP-D4).

    * `programmes` – the seller's programme: title, summary, price, where it
      is listed, its refund rule and the version on sale;
    * `programme_versions` – immutable published versions: the weeks and,
      per day, the frozen copy of each structured WOD;
    * `programme_purchases` – one buyer's purchase of one version: payment,
      start date, withdrawal record, refunds;
    * `programme_deliveries` – the WODs a purchase scheduled for its buyer
      (assigned workouts), so a refund removes the future ones;
    * `programme_reviews` – one review per purchase.

  `palee_marketplace_programmes` is the cross-business catalogue: a
  SECURITY DEFINER function that projects public fields of published,
  marketplace-listed programmes only (like the ADR-154 `palee_around_*`).
  It pins only `search_path`.

  Payment intents gain the purpose `programme` (the existing check is
  rewritten from its current definition, so other additions survive).
  """

  use Ecto.Migration

  @tables ~w(programmes programme_versions programme_purchases programme_deliveries programme_reviews)

  def up do
    create table(:programmes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :title, :string, size: 120, null: false
      add :summary, :string, size: 600
      add :description, :text
      add :level, :string, null: false, default: "all"
      add :goal, :string, null: false, default: "general"
      add :equipment, {:array, :string}, null: false, default: []
      add :sessions_per_week, :integer
      add :price_cents, :integer, null: false, default: 0
      add :currency, :string, size: 3, null: false, default: "EUR"
      add :listing, :string, null: false, default: "box"
      add :status, :string, null: false, default: "draft"
      add :preview_days, :integer, null: false, default: 3
      add :refund_policy, :string, null: false, default: "before_start"
      # The days being written, before they are published as a version.
      add :draft_weeks, :integer, null: false, default: 4
      add :draft_days, :map, null: false, default: fragment("'[]'::jsonb")
      add :current_version_id, :binary_id
      add :published_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:programmes, [:id, :organization_id],
             name: :programmes_id_organization_index
           )

    create index(:programmes, [:organization_id, :status])

    create index(:programmes, [:listing, :status],
             where: "status = 'published' AND listing = 'marketplace'",
             name: :programmes_marketplace_index
           )

    create constraint(:programmes, :programmes_check,
             check: """
             status IN ('draft', 'published', 'archived')
             AND listing IN ('box', 'marketplace')
             AND level IN ('all', 'beginner', 'intermediate', 'advanced')
             AND goal IN ('general', 'strength', 'conditioning', 'gymnastics', 'weightlifting',
                          'endurance', 'competition', 'hyrox', 'mobility')
             AND refund_policy IN ('before_start', 'withdrawal_only', 'pro_rata')
             AND currency IN ('EUR', 'GBP', 'USD', 'CHF')
             AND price_cents >= 0 AND price_cents <= 10000000
             AND preview_days BETWEEN 0 AND 14
             AND draft_weeks BETWEEN 1 AND 52 AND jsonb_typeof(draft_days) = 'array'
             AND (sessions_per_week IS NULL OR sessions_per_week BETWEEN 1 AND 14)
             AND (status <> 'published' OR current_version_id IS NOT NULL)
             """
           )

    create table(:programme_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :programme_id, :binary_id, null: false
      add :number, :integer, null: false
      add :weeks, :integer, null: false
      add :days, :map, null: false
      add :changelog, :string, size: 600
      add :published_at, :utc_datetime_usec, null: false
      add :published_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE programme_versions
    ADD CONSTRAINT programme_versions_programme_fkey
    FOREIGN KEY (programme_id, organization_id)
    REFERENCES programmes (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:programme_versions, [:id, :organization_id],
             name: :programme_versions_id_organization_index
           )

    create unique_index(:programme_versions, [:programme_id, :number])

    create constraint(:programme_versions, :programme_versions_check,
             check: "number >= 1 AND weeks BETWEEN 1 AND 52 AND jsonb_typeof(days) = 'array'"
           )

    # A published version is what buyers paid for: never changed, never deleted
    # while its programme exists.
    execute("""
    CREATE OR REPLACE FUNCTION palee_programme_versions_immutable() RETURNS trigger
    LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
    BEGIN
      RAISE EXCEPTION 'programme versions are immutable' USING ERRCODE = '55000';
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER programme_versions_immutable
    BEFORE UPDATE ON programme_versions
    FOR EACH ROW EXECUTE FUNCTION palee_programme_versions_immutable()
    """)

    execute("""
    ALTER TABLE programmes
    ADD CONSTRAINT programmes_current_version_fkey
    FOREIGN KEY (current_version_id, organization_id)
    REFERENCES programme_versions (id, organization_id)
    DEFERRABLE INITIALLY DEFERRED
    """)

    create table(:programme_purchases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :programme_id, :binary_id, null: false
      add :version_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending_payment"
      add :price_cents, :integer, null: false
      add :currency, :string, size: 3, null: false
      add :refund_policy, :string, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :payment_intent_id, :binary_id
      add :finance_payment_id, :binary_id
      add :fiscal_document_id, :binary_id
      add :withdrawal, :map, null: false, default: %{}
      add :refunded_cents, :integer, null: false, default: 0
      add :idempotency_key, :string, size: 200, null: false
      add :activated_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :end_reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE programme_purchases
    ADD CONSTRAINT programme_purchases_programme_fkey
    FOREIGN KEY (programme_id, organization_id)
    REFERENCES programmes (id, organization_id) ON DELETE RESTRICT
    """)

    execute("""
    ALTER TABLE programme_purchases
    ADD CONSTRAINT programme_purchases_version_fkey
    FOREIGN KEY (version_id, organization_id)
    REFERENCES programme_versions (id, organization_id) ON DELETE RESTRICT
    """)

    create unique_index(:programme_purchases, [:id, :organization_id],
             name: :programme_purchases_id_organization_index
           )

    create unique_index(:programme_purchases, [:organization_id, :idempotency_key])

    create unique_index(:programme_purchases, [:payment_intent_id],
             where: "payment_intent_id IS NOT NULL"
           )

    create index(:programme_purchases, [:organization_id, :user_id])
    create index(:programme_purchases, [:programme_id, :status])

    create constraint(:programme_purchases, :programme_purchases_check,
             check: """
             status IN ('pending_payment', 'active', 'completed', 'withdrawn', 'refunded',
                        'cancelled')
             AND refund_policy IN ('before_start', 'withdrawal_only', 'pro_rata')
             AND currency IN ('EUR', 'GBP', 'USD', 'CHF')
             AND price_cents > 0
             AND refunded_cents >= 0 AND refunded_cents <= price_cents
             AND ends_on >= starts_on
             AND (status IN ('pending_payment', 'cancelled') OR activated_at IS NOT NULL)
             AND (end_reason IS NULL OR end_reason IN ('completed', 'withdrawn', 'refunded',
                                                       'cancelled', 'expired'))
             """
           )

    create table(:programme_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :purchase_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :assigned_workout_id, :binary_id, null: false
      add :day, :integer, null: false
      add :scheduled_for, :date, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE programme_deliveries
    ADD CONSTRAINT programme_deliveries_purchase_fkey
    FOREIGN KEY (purchase_id, organization_id)
    REFERENCES programme_purchases (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:programme_deliveries, [:purchase_id, :day, :assigned_workout_id])
    create index(:programme_deliveries, [:purchase_id, :scheduled_for])

    create table(:programme_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :programme_id, :binary_id, null: false
      add :purchase_id, :binary_id, null: false
      # A deleted account takes its reviews with it (their text is the person's).
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :version_number, :integer, null: false
      add :rating, :integer, null: false
      add :body, :string, size: 1000
      add :status, :string, null: false, default: "published"
      add :hidden_reason, :string, size: 300
      add :hidden_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE programme_reviews
    ADD CONSTRAINT programme_reviews_programme_fkey
    FOREIGN KEY (programme_id, organization_id)
    REFERENCES programmes (id, organization_id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE programme_reviews
    ADD CONSTRAINT programme_reviews_purchase_fkey
    FOREIGN KEY (purchase_id, organization_id)
    REFERENCES programme_purchases (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:programme_reviews, [:purchase_id])
    create index(:programme_reviews, [:programme_id, :status])

    create constraint(:programme_reviews, :programme_reviews_check,
             check: """
             rating BETWEEN 1 AND 5 AND status IN ('published', 'hidden')
             AND (status <> 'hidden' OR hidden_reason IS NOT NULL)
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

    # The cross-business catalogue: public fields of published marketplace
    # programmes of active businesses, with their published reviews' average.
    execute("""
    CREATE OR REPLACE FUNCTION palee_marketplace_programmes(
      p_query text, p_goal text, p_level text, p_limit integer, p_offset integer)
    RETURNS TABLE (
      id uuid, organization_id uuid, organization_slug text, organization_name text,
      title text, summary text, level text, goal text, equipment text[],
      sessions_per_week integer, price_cents integer, currency text, weeks integer,
      version_number integer, rating_average numeric, rating_count bigint,
      published_at timestamptz)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
      SELECT p.id, p.organization_id, o.slug::text, o.name::text,
             p.title::text, p.summary::text, p.level::text, p.goal::text, p.equipment,
             p.sessions_per_week, p.price_cents, p.currency::text, v.weeks, v.number,
             round(avg(r.rating)::numeric, 1), count(r.id), p.published_at
      FROM programmes p
      JOIN organizations o ON o.id = p.organization_id
      JOIN programme_versions v ON v.id = p.current_version_id
      LEFT JOIN programme_reviews r ON r.programme_id = p.id AND r.status = 'published'
      WHERE p.status = 'published' AND p.listing = 'marketplace' AND p.price_cents > 0
        AND o.status = 'active' AND o.activation = 'active'
        AND (p_goal IS NULL OR p.goal = p_goal)
        AND (p_level IS NULL OR p.level = p_level)
        AND (p_query IS NULL OR p.title ILIKE '%' || p_query || '%'
             OR p.summary ILIKE '%' || p_query || '%')
      GROUP BY p.id, o.slug, o.name, v.weeks, v.number
      ORDER BY p.published_at DESC, p.id
      LIMIT LEAST(GREATEST(p_limit, 1), 50) OFFSET GREATEST(p_offset, 0)
    $$
    """)

    add_programme_purpose()
  end

  def down do
    execute(
      "DROP FUNCTION IF EXISTS palee_marketplace_programmes(text, text, text, integer, integer)"
    )

    execute("ALTER TABLE programmes DROP CONSTRAINT IF EXISTS programmes_current_version_fkey")

    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))

    execute("DROP FUNCTION IF EXISTS palee_programme_versions_immutable()")
    remove_programme_purpose()
  end

  # Rewrites the current payment_intents check (whatever other migrations
  # added to it) with 'programme' among the purposes.
  defp add_programme_purpose do
    execute("""
    DO $$
    DECLARE definition text;
    BEGIN
      SELECT pg_get_constraintdef(oid) INTO definition FROM pg_constraint
      WHERE conname = 'payment_intents_check' AND conrelid = 'payment_intents'::regclass;
      IF definition IS NOT NULL AND position('''programme''' in definition) = 0 THEN
        definition := regexp_replace(definition,
          '''shop_order''::character varying',
          '''shop_order''::character varying, ''programme''::character varying');
        ALTER TABLE payment_intents DROP CONSTRAINT payment_intents_check;
        EXECUTE 'ALTER TABLE payment_intents ADD CONSTRAINT payment_intents_check ' || definition;
      END IF;
    END $$
    """)
  end

  defp remove_programme_purpose do
    execute("""
    DO $$
    DECLARE definition text;
    BEGIN
      SELECT pg_get_constraintdef(oid) INTO definition FROM pg_constraint
      WHERE conname = 'payment_intents_check' AND conrelid = 'payment_intents'::regclass;
      IF definition IS NOT NULL AND position('''programme''' in definition) > 0 THEN
        definition := replace(definition, ', ''programme''::character varying', '');
        ALTER TABLE payment_intents DROP CONSTRAINT payment_intents_check;
        EXECUTE 'ALTER TABLE payment_intents ADD CONSTRAINT payment_intents_check ' || definition;
      END IF;
    END $$
    """)
  end
end
