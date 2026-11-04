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

  @doc "The inbox list's filter parameters (ADR-460)."
  def filter_params do
    [
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
      properties: %{state: state(), older_than_days: older_than_days(), category: category()},
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
                "matches, as the list shows them), never both. Not undoable.",
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
         properties: %{deleted_count: %Schema{type: :integer, minimum: 0}},
         required: [:deleted_count]
       }}

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
