defmodule Palee.Repo.Migrations.CreateHelpDesk do
  @moduledoc """
  ADR-363: in-app support with an AI first line.

    * `help_desk_conversations` – a staff person's conversation with
      Palee support, with the screen it was opened from;
    * `help_desk_messages` – its messages: the person's, the assistant's
      (with the help articles it cited) and the Palee team's. Insert-only;
    * `help_desk_tickets` – a conversation handed to the Palee team, with
      its context, state and who on the team has it.

  All three are tenant tables (forced RLS, `palee_apply_tenant_context`).
  The tickets policy also admits the Palee team
  (`palee_acting_user_is_vendor()`), whose console lists tickets across
  boxes; it reads a ticket's messages in that box's own session. Every row
  goes with the box (ADR-117) and a conversation goes with its person.
  """

  use Ecto.Migration

  @org "NULLIF(current_setting('app.organization_id', true), '')::uuid"

  def up do
    create table(:help_desk_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :text, null: false, default: "assistant"
      add :locale, :text, null: false
      add :screen_path, :text
      add :subject, :text, null: false
      add :last_message_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:help_desk_conversations, [:id, :organization_id],
             name: :help_desk_conversations_id_organization_index
           )

    create index(:help_desk_conversations, [:organization_id, :user_id, :last_message_at])

    create constraint(:help_desk_conversations, :help_desk_conversations_check,
             check: """
             status IN ('assistant', 'waiting_for_palee', 'answered_by_palee', 'resolved')
             AND char_length(locale) BETWEEN 2 AND 5
             AND (screen_path IS NULL OR char_length(screen_path) <= 300)
             AND char_length(subject) BETWEEN 1 AND 160
             """
           )

    create table(:help_desk_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :conversation_id, :binary_id, null: false
      add :author, :text, null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :body, :text, null: false
      add :citations, {:array, :map}, null: false, default: []
      add :guide_id, :text
      add :confident, :boolean
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE help_desk_messages
    ADD CONSTRAINT help_desk_messages_conversation_fkey
    FOREIGN KEY (conversation_id, organization_id)
    REFERENCES help_desk_conversations (id, organization_id) ON DELETE CASCADE
    """)

    create index(:help_desk_messages, [:conversation_id, :inserted_at])

    create constraint(:help_desk_messages, :help_desk_messages_check,
             check: """
             author IN ('person', 'assistant', 'palee')
             AND char_length(body) BETWEEN 1 AND 4000
             AND cardinality(citations) <= 10
             AND (guide_id IS NULL OR guide_id ~ '^[a-z][a-z0-9_]{1,47}$')
             """
           )

    create table(:help_desk_tickets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :conversation_id, :binary_id, null: false
      add :requester_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :status, :text, null: false, default: "open"
      add :priority, :text, null: false, default: "normal"
      add :summary, :text, null: false
      add :screen_path, :text
      add :locale, :text, null: false
      add :client_context, :map, null: false, default: %{}
      add :articles_tried, {:array, :text}, null: false, default: []
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :first_response_at, :utc_datetime_usec
      add :solved_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE help_desk_tickets
    ADD CONSTRAINT help_desk_tickets_conversation_fkey
    FOREIGN KEY (conversation_id, organization_id)
    REFERENCES help_desk_conversations (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:help_desk_tickets, [:conversation_id])
    create index(:help_desk_tickets, [:status, :inserted_at])
    create index(:help_desk_tickets, [:organization_id, :status])

    create constraint(:help_desk_tickets, :help_desk_tickets_check,
             check: """
             status IN ('open', 'waiting_on_box', 'solved')
             AND priority IN ('normal', 'urgent')
             AND char_length(summary) BETWEEN 1 AND 1000
             AND (screen_path IS NULL OR char_length(screen_path) <= 300)
             AND char_length(locale) BETWEEN 2 AND 5
             AND cardinality(articles_tried) <= 20
             AND (status <> 'solved' OR solved_at IS NOT NULL)
             """
           )

    for table <- ~w(help_desk_conversations help_desk_messages help_desk_tickets) do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      scope =
        if table == "help_desk_tickets",
          do: "(organization_id = #{@org} OR palee_acting_user_is_vendor())",
          else: "(organization_id = #{@org})"

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING #{scope}
      WITH CHECK #{scope}
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  def down do
    drop table(:help_desk_tickets)
    drop table(:help_desk_messages)
    drop table(:help_desk_conversations)
  end
end
