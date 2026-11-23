defmodule PaleeWeb.Schemas.ActivityLog do
  @moduledoc "ADR-760: «Αρχείο ενεργειών» payloads."

  alias OpenApiSpex.Schema
  alias Palee.ActivityLog.Domain.Actions

  @at %Schema{type: :string, format: :"date-time"}

  defp area, do: %Schema{type: :string, enum: Enum.map(Actions.areas(), &Atom.to_string/1)}
  defp action, do: %Schema{type: :string, enum: Actions.keys()}

  defp person do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, nullable: true}
      },
      required: [:id, :name]
    }
  end

  @changes %Schema{
    type: :array,
    items: %Schema{
      type: :object,
      properties: %{
        field: %Schema{type: :string},
        before: %Schema{type: :string, nullable: true},
        after: %Schema{type: :string, nullable: true}
      },
      required: [:field]
    }
  }

  defp details do
    %Schema{
      type: :object,
      additionalProperties: true,
      description:
        "What the use case added: `changes` (field, before, after as text), and keys of its own (e.g. `kind`, `starts_on`, `ends_on`, `amount_cents`)",
      properties: %{changes: @changes}
    }
  end

  def entry do
    %Schema{
      title: "ActivityLogEntry",
      type: :object,
      description: "One change staff made: who, what, when, to whom and why (insert-only)",
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        occurred_at: @at,
        action: action(),
        area: area(),
        actor: %Schema{
          type: :object,
          nullable: true,
          description: "Who on the staff did it, with their roles then; null for the system",
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            name: %Schema{type: :string, nullable: true},
            roles: %Schema{type: :array, items: %Schema{type: :string}}
          },
          required: [:id, :name, :roles]
        },
        person: person(),
        subject: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string},
          description: "The ids the request named (path parameters)"
        },
        subject_label: %Schema{type: :string, nullable: true},
        details: details(),
        reason: %Schema{type: :string, nullable: true},
        reason_shared: %Schema{type: :boolean, description: "The member sees this row (5A)"},
        sensitive: %Schema{type: :boolean, description: "In the owner's daily summary (12B)"},
        source: %Schema{type: :string, enum: ["request", "backfill", "system"]},
        redacted: %Schema{
          type: :boolean,
          description: "The person's account was deleted: reason and details are gone (9A)"
        }
      },
      required: [
        :id,
        :occurred_at,
        :action,
        :area,
        :actor,
        :person,
        :subject,
        :subject_label,
        :details,
        :reason,
        :reason_shared,
        :sensitive,
        :source,
        :redacted
      ]
    }
  end

  def member_entry do
    %Schema{
      title: "MemberActivityEntry",
      type: :object,
      description:
        "A change the box shared with the member; who on the staff did it is not shown",
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        occurred_at: @at,
        action: action(),
        area: area(),
        person: person(),
        subject: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        subject_label: %Schema{type: :string, nullable: true},
        details: details(),
        reason: %Schema{type: :string, nullable: true},
        redacted: %Schema{type: :boolean}
      },
      required: [
        :id,
        :occurred_at,
        :action,
        :area,
        :person,
        :subject,
        :subject_label,
        :details,
        :reason,
        :redacted
      ]
    }
  end

  def page do
    %Schema{
      title: "ActivityLogPage",
      type: :object,
      properties: %{
        entries: %Schema{type: :array, items: entry()},
        next_cursor: %Schema{type: :string, nullable: true},
        can_export: %Schema{type: :boolean},
        areas: %Schema{type: :array, items: area(), description: "The areas this reader may see"}
      },
      required: [:entries, :next_cursor, :can_export, :areas]
    }
  end

  def member_page do
    %Schema{
      title: "MemberActivityPage",
      type: :object,
      properties: %{
        entries: %Schema{type: :array, items: member_entry()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:entries, :next_cursor]
    }
  end
end
