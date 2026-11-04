defmodule Palee.Repo.Migrations.ContentTranslations do
  @moduledoc """
  ADR-520: translations of the texts a box writes for its website, in any
  language of the app, one row per text, field and language.

    * `content_translations` – the translated text, the hash of the source it
      was made from (a changed source shows the translation as out of date),
      whether a person wrote it or a machine (and when a person checked it);
    * `box_site_settings.translation_locales` / `visible_locales` – the
      languages the owner translates into and the ones visitors can pick;
    * every FAQ entry gets a stable `id`, so translations follow an entry
      when the owner reorders the list;
    * the English texts of ADR-388 (`about_en`, `faq[].question_en/answer_en`)
      move into `content_translations`; the next migration drops `about_en`.

  Existing boxes keep English visible, as before.
  """

  use Ecto.Migration

  @table "content_translations"

  def up do
    create table(:content_translations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subject_kind, :string, size: 40, null: false
      add :subject_id, :binary_id, null: false
      add :field, :string, size: 40, null: false
      add :locale, :string, size: 10, null: false
      add :text, :text, null: false
      add :source_hash, :string, size: 64, null: false
      add :origin, :string, size: 10, null: false
      add :reviewed_at, :utc_datetime_usec
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:content_translations, [
             :organization_id,
             :locale,
             :subject_kind,
             :subject_id,
             :field
           ])

    create index(:content_translations, [:organization_id, :subject_kind, :subject_id])

    create constraint(:content_translations, :content_translations_check,
             check: """
             origin IN ('manual', 'machine')
             AND char_length(text) BETWEEN 1 AND 4000
             AND source_hash ~ '^[0-9a-f]{64}$'
             AND locale ~ '^[a-z]{2}(-[A-Z]{2})?$'
             AND (origin = 'machine' OR reviewed_at IS NOT NULL)
             """
           )

    execute("""
    CREATE TRIGGER #{@table}_apply_tenant_context
    BEFORE INSERT OR UPDATE ON #{@table}
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY #{@table}_tenant_policy ON #{@table}
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE #{@table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{@table} FORCE ROW LEVEL SECURITY")

    alter table(:box_site_settings) do
      add :translation_locales, {:array, :string}, null: false, default: ["en"]
      add :visible_locales, {:array, :string}, null: false, default: ["en"]
    end

    create constraint(:box_site_settings, :box_site_settings_locales_check,
             check: """
             cardinality(translation_locales) <= 11
             AND visible_locales <@ translation_locales
             """
           )

    flush()

    # Stable ids for FAQ entries.
    execute("""
    UPDATE box_site_settings s
    SET faq = jsonb_build_object('entries', (
      SELECT coalesce(jsonb_agg(
        CASE WHEN e ? 'id' THEN e ELSE e || jsonb_build_object('id', gen_random_uuid()) END
        ORDER BY ord), '[]'::jsonb)
      FROM jsonb_array_elements(coalesce(s.faq -> 'entries', '[]'::jsonb)) WITH ORDINALITY AS t(e, ord)
    ))
    """)

    # The English «Σχετικά» (source: the published about text).
    execute("""
    INSERT INTO content_translations
      (id, organization_id, subject_kind, subject_id, field, locale, text, source_hash,
       origin, reviewed_at, updated_by_id, inserted_at, updated_at)
    SELECT gen_random_uuid(), s.organization_id, 'box_profile', s.organization_id, 'about', 'en',
           s.about_en,
           encode(sha256(convert_to(coalesce(p.published_snapshot ->> 'about', ''), 'UTF8')), 'hex'),
           'manual', s.updated_at, s.updated_by_id, now(), now()
    FROM box_site_settings s
    LEFT JOIN organization_public_profiles p ON p.organization_id = s.organization_id
    WHERE s.about_en IS NOT NULL AND btrim(s.about_en) <> ''
    """)

    # The English FAQ halves.
    for {field, key} <- [{"question", "question_en"}, {"answer", "answer_en"}] do
      execute("""
      INSERT INTO content_translations
        (id, organization_id, subject_kind, subject_id, field, locale, text, source_hash,
         origin, reviewed_at, updated_by_id, inserted_at, updated_at)
      SELECT gen_random_uuid(), s.organization_id, 'site_faq', (e ->> 'id')::uuid, '#{field}', 'en',
             e ->> '#{key}',
             encode(sha256(convert_to(coalesce(e ->> '#{field}', ''), 'UTF8')), 'hex'),
             'manual', s.updated_at, s.updated_by_id, now(), now()
      FROM box_site_settings s,
           jsonb_array_elements(coalesce(s.faq -> 'entries', '[]'::jsonb)) AS e
      WHERE coalesce(btrim(e ->> '#{key}'), '') <> ''
      """)
    end

    execute("""
    UPDATE box_site_settings
    SET faq = jsonb_build_object('entries', (
      SELECT coalesce(jsonb_agg((e - 'question_en' - 'answer_en') ORDER BY ord), '[]'::jsonb)
      FROM jsonb_array_elements(coalesce(faq -> 'entries', '[]'::jsonb)) WITH ORDINALITY AS t(e, ord)
    ))
    """)
  end

  def down do
    # The English texts go back where ADR-388 kept them.
    execute("""
    UPDATE box_site_settings s
    SET faq = jsonb_build_object('entries', (
      SELECT coalesce(jsonb_agg(
        e
        || coalesce((SELECT jsonb_build_object('question_en', q.text) FROM content_translations q
                     WHERE q.organization_id = s.organization_id AND q.locale = 'en'
                       AND q.subject_kind = 'site_faq' AND q.subject_id = (e ->> 'id')::uuid
                       AND q.field = 'question'), '{}'::jsonb)
        || coalesce((SELECT jsonb_build_object('answer_en', a.text) FROM content_translations a
                     WHERE a.organization_id = s.organization_id AND a.locale = 'en'
                       AND a.subject_kind = 'site_faq' AND a.subject_id = (e ->> 'id')::uuid
                       AND a.field = 'answer'), '{}'::jsonb)
        ORDER BY ord), '[]'::jsonb)
      FROM jsonb_array_elements(coalesce(s.faq -> 'entries', '[]'::jsonb)) WITH ORDINALITY AS t(e, ord)
    ))
    """)

    execute("""
    UPDATE box_site_settings s SET about_en = t.text
    FROM content_translations t
    WHERE t.organization_id = s.organization_id AND t.locale = 'en'
      AND t.subject_kind = 'box_profile' AND t.field = 'about'
    """)

    drop constraint(:box_site_settings, :box_site_settings_locales_check)

    alter table(:box_site_settings) do
      remove :visible_locales
      remove :translation_locales
    end

    drop table(:content_translations)
  end
end
