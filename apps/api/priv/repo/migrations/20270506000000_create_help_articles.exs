defmodule Palee.Repo.Migrations.CreateHelpArticles do
  @moduledoc """
  ADR-362: the help centre. `help_articles` is platform content written by
  the Palee team (no tenant): one row per article and locale, with the
  feature it explains, the in-app guide it can open and the screens
  (route patterns) it is linked from.

  Row security: published articles are readable by anyone; drafts and
  every write belong to the Palee team (`palee_acting_user_is_vendor()`)
  or the system (no acting person: seeding, jobs), as `platform_plans`
  does. Functions pin only `search_path` (none are created here).
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')"

  def up do
    create table(:help_articles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :text, null: false
      add :locale, :text, null: false
      add :title, :text, null: false
      add :summary, :text, null: false
      add :body, :text, null: false, default: ""
      add :audience, :text, null: false, default: "staff"
      add :feature_key, :text
      add :guide_id, :text
      add :screens, {:array, :text}, null: false, default: []
      add :keywords, {:array, :text}, null: false, default: []
      add :status, :text, null: false, default: "draft"
      add :source, :text, null: false, default: "palee"
      add :complete, :boolean, null: false, default: true
      add :version, :integer, null: false, default: 1
      add :position, :integer, null: false, default: 100
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :published_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:help_articles, [:slug, :locale])
    create index(:help_articles, [:locale, :status, :position])
    execute("CREATE INDEX help_articles_screens_index ON help_articles USING gin (screens)")

    create constraint(:help_articles, :help_articles_check,
             check: """
             slug ~ '^[a-z0-9][a-z0-9-]{1,79}$'
             AND locale IN ('en','el','ar','ru','de','es','pt-PT','he','it','bg','nl','fr')
             AND char_length(title) BETWEEN 1 AND 160
             AND char_length(summary) BETWEEN 1 AND 500
             AND char_length(body) <= 20000
             AND audience IN ('staff', 'member', 'all')
             AND status IN ('draft', 'published')
             AND source IN ('seed', 'palee')
             AND version BETWEEN 1 AND 100000
             AND (guide_id IS NULL OR guide_id ~ '^[a-z][a-z0-9_]{1,47}$')
             AND cardinality(screens) <= 20
             AND cardinality(keywords) <= 30
             AND (status <> 'published' OR published_at IS NOT NULL)
             """
           )

    execute("""
    CREATE POLICY help_articles_read_policy ON help_articles
      FOR SELECT
      USING (status = 'published' OR #{@acting_user} IS NULL OR palee_acting_user_is_vendor())
    """)

    for {name, command, clause} <- [
          {"insert", "INSERT", "WITH CHECK"},
          {"update", "UPDATE", "USING"},
          {"delete", "DELETE", "USING"}
        ] do
      check =
        if command == "UPDATE",
          do:
            "USING (#{@acting_user} IS NULL OR palee_acting_user_is_vendor()) " <>
              "WITH CHECK (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())",
          else: "#{clause} (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())"

      execute(
        "CREATE POLICY help_articles_#{name}_policy ON help_articles FOR #{command} #{check}"
      )
    end

    execute("ALTER TABLE help_articles ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE help_articles FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:help_articles)
  end
end
