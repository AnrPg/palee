defmodule PaleeWeb.Schemas.Notifications do
  @moduledoc """
  OpenAPI schemas of deleting notifications (ADR-460): the bell's trash
  button and «Αναίρεση», the delete card of Ρυθμίσεις with its filter, and
  the filter parameters of the inbox list.
  """

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias Palee.Notifications

  def id_param,
    do: %Parameter{
      name: :id,
      in: :path,
      required: true,
      description: "Notification ID",
      schema: %Schema{type: :string, format: :uuid}
    }

  defp state,
    do: %Schema{
      type: :string,
      enum: ["all", "read"],
      description: "`read`: only notifications already read. Default `all`."
    }

  defp older_than_days,
    do: %Schema{
      type: :integer,
      minimum: 1,
      maximum: 3650,
      description: "Only notifications received more than this many days ago."
    }

  defp category,
    do: %Schema{
      type: :string,
      enum: Notifications.notification_categories(),
      description: "Only notifications of this category (ADR-199)."
    }

  defp group_key,
    do: %Schema{
      type: :string,
      minLength: 1,
      maxLength: 400,
      description: "ADR-600: only the notifications of this stack (its `stack.key`)."
    }

  defp types,
    do: %Schema{
      type: :string,
      maxLength: 4000,
      description:
        "ADR-600: only notifications of these types, comma-separated (the bell's tabs)."
    }

  @doc "The inbox list's filter parameters (ADR-460, ADR-600)."
  def filter_params do
    [
      %Parameter{name: :group_key, in: :query, required: false, schema: group_key()},
      %Parameter{name: :types, in: :query, required: false, schema: types()},
      %Parameter{
        name: :stacks,
        in: :query,
        required: false,
        description:
          "ADR-600: one row per stack of similar notifications (its newest, with `stack`).",
        schema: %Schema{type: :boolean}
      },
      %Parameter{name: :state, in: :query, required: false, schema: state()},
      %Parameter{name: :older_than_days, in: :query, required: false, schema: older_than_days()},
      %Parameter{name: :category, in: :query, required: false, schema: category()},
      %Parameter{
        name: :include_count,
        in: :query,
        required: false,
        description: "Also answer `matching_count`: how many notifications match the filter.",
        schema: %Schema{type: :boolean}
      }
    ]
  end

  def filter do
    %Schema{
      title: "NotificationFilter",
      type: :object,
      description: "Which notifications a bulk delete covers; an empty filter covers all.",
      properties: %{
        state: state(),
        older_than_days: older_than_days(),
        category: category(),
        group_key: group_key(),
        types: types()
      },
      additionalProperties: false
    }
  end

  def bulk_delete_request do
    %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            title: "NotificationBulkDelete",
            type: :object,
            description:
              "Either `ids` (the notifications picked) or `filter` (every notification it " <>
                "matches, as the list shows them), never both. A `filter` delete may be " <>
                "restored for `restorable_for_seconds` (ADR-600).",
            properties: %{
              ids: %Schema{
                type: :array,
                minItems: 1,
                maxItems: Notifications.bulk_delete_max_ids(),
                items: %Schema{type: :string, format: :uuid}
              },
              filter: filter()
            }
          }
        }
      }
    }
  end

  def deleted_count_response,
    do:
      {"Deleted count", "application/json",
       %Schema{
         title: "NotificationDeletedCount",
         type: :object,
         properties: %{
           deleted_count: %Schema{type: :integer, minimum: 0},
           restorable_for_seconds: %Schema{
             type: :integer,
             description: "How long «Αναίρεση» may still restore them (ADR-600)."
           }
         },
         required: [:deleted_count, :restorable_for_seconds]
       }}

  @doc "ADR-600: the body of a stack's closed eye and of its «Αναίρεση»."
  def filter_request(title),
    do: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            title: title,
            type: :object,
            properties: %{filter: filter()},
            required: [:filter]
          }
        }
      }
    }

  def marked_count_response,
    do:
      {"Read count", "application/json",
       %Schema{
         title: "NotificationMarkedCount",
         type: :object,
         properties: %{marked_count: %Schema{type: :integer, minimum: 0}},
         required: [:marked_count]
       }}

  def restored_count_response,
    do:
      {"Restored count", "application/json",
       %Schema{
         title: "NotificationRestoredCount",
         type: :object,
         properties: %{restored_count: %Schema{type: :integer, minimum: 0}},
         required: [:restored_count]
       }}

  @doc "ADR-600: a row of the stacked inbox that stands for a stack."
  def stack,
    do: %Schema{
      title: "NotificationStack",
      type: :object,
      nullable: true,
      properties: %{
        key: %Schema{type: :string},
        count: %Schema{type: :integer, minimum: 1},
        unread_count: %Schema{type: :integer, minimum: 0}
      },
      required: [:count, :key, :unread_count]
    }

  def deleted_response,
    do:
      {"Delete result", "application/json",
       %Schema{
         title: "NotificationDeleted",
         type: :object,
         properties: %{
           deleted: %Schema{type: :boolean},
           restorable_for_seconds: %Schema{
             type: :integer,
             description: "How long «Αναίρεση» may still restore it."
           }
         },
         required: [:deleted, :restorable_for_seconds]
       }}

  def restored_response,
    do:
      {"Restore result", "application/json",
       %Schema{
         title: "NotificationRestored",
         type: :object,
         properties: %{restored: %Schema{type: :boolean}},
         required: [:restored]
       }}

  def error_response(description),
    do:
      {description, "application/json",
       %Schema{
         type: :object,
         properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
         required: [:error]
       }}
end
