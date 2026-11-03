defmodule Palee.Application.Operations.KeyDescribe do
  @moduledoc """
  ADR-378 `key.describe` (`GET /me`): which box and scopes a key has.
  Zapier and Make call it to test the connection and label the account.
  """

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Organizations

  @impl true
  def spec do
    %{
      name: "key.describe",
      kind: :query,
      summary: "Describe this key and its box",
      description:
        "The box (id, name, time zone) and the key's name and scopes. Needs no scope, so it " <>
          "is the connection test for Zapier and Make.",
      capability: [
        :view_directory,
        :manage_settings,
        :manage_schedule,
        :run_classes,
        :book_for_clients,
        :view_package_catalog,
        :manage_billing,
        :view_finance_reports
      ],
      scope: "any",
      risk: :read,
      data_classes: [],
      http: %{method: :get, path: "/me"},
      input: %{"type" => "object", "additionalProperties" => false, "properties" => %{}},
      output: %{
        "type" => "object",
        "properties" => %{
          "box" => %{
            "type" => "object",
            "properties" => %{
              "id" => Views.uuid(),
              "name" => %{"type" => "string"},
              "slug" => %{"type" => "string"},
              "time_zone" => %{"type" => "string"}
            },
            "required" => ["id", "name", "slug", "time_zone"]
          },
          "key" => %{
            "type" => ["object", "null"],
            "properties" => %{
              "name" => %{"type" => "string"},
              "prefix" => %{"type" => "string"},
              "scopes" => %{"type" => "array", "items" => %{"type" => "string"}}
            },
            "required" => ["name", "prefix", "scopes"]
          }
        },
        "required" => ["box", "key"]
      },
      examples: [%{input: %{}, output: %{}}]
    }
  end

  @impl true
  def execute(context, _input) do
    organization = Map.get(context, :organization) || %{}

    key =
      case Map.get(context, :principal) do
        %{kind: :api_key} = principal ->
          %{"name" => principal.name, "prefix" => principal.prefix, "scopes" => principal.scopes}

        _person ->
          nil
      end

    {:ok,
     %{
       "box" => %{
         "id" => context.organization_id,
         "name" => Map.get(organization, :name),
         "slug" => Map.get(organization, :slug),
         "time_zone" => Organizations.organization_timezone(context.organization_id)
       },
       "key" => key
     }}
  end
end
