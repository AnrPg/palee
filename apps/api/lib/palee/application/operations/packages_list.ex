defmodule Palee.Application.Operations.PackagesList do
  @moduledoc "ADR-378 `packages.list`: the box's packages (the catalogue)."

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Finance

  @impl true
  def spec do
    %{
      name: "packages.list",
      kind: :query,
      summary: "List the box's packages",
      description:
        "Every package the box offers or offered (active false), with its price in cents. " <>
          "Use the id with member_packages.assign.",
      capability: [:view_package_catalog, :manage_packages],
      scope: "packages:read",
      risk: :read,
      data_classes: [],
      http: %{method: :get, path: "/packages"},
      input: %{"type" => "object", "additionalProperties" => false, "properties" => %{}},
      output: %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "array", "items" => Views.package_schema()}},
        "required" => ["data"]
      },
      examples: [%{input: %{}, output: %{}}]
    }
  end

  @impl true
  def execute(context, _input) do
    packages = context |> Finance.list_packages() |> List.wrap()
    {:ok, %{"data" => Enum.map(packages, &Views.package(&1, "EUR"))}}
  end
end
