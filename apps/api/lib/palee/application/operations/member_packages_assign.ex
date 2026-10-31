defmodule Palee.Application.Operations.MemberPackagesAssign do
  @moduledoc """
  ADR-378 `member_packages.assign`: gives a member a package, as the desk
  does (wraps `AssignFinanceMemberPackage`). The price is the package's;
  an API key cannot set a price or take a payment.
  """

  @behaviour Palee.Operations.Operation

  alias Palee.Application.AssignFinanceMemberPackage
  alias Palee.Application.Operations.Views
  alias Palee.Finance

  @impl true
  def spec do
    %{
      name: "member_packages.assign",
      kind: :command,
      summary: "Give a member a package",
      description:
        "Starts the package for the member at its catalogue price, as the desk does; an " <>
          "invoice follows the box's billing settings. Use it after a sale made elsewhere. " <>
          "It creates a charge, so send an Idempotency-Key.",
      capability: [:manage_billing, :take_payments],
      scope: "packages:write",
      risk: :money,
      data_classes: [:personal, :financial],
      http: %{method: :post, path: "/members/{member_id}/packages", status: 201},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "member_id" => Views.uuid(),
          "package_id" => Views.uuid(),
          "starts_on" => %{"type" => "string", "format" => "date"}
        },
        "required" => ["member_id", "package_id"]
      },
      output: %{
        "type" => "object",
        "properties" => %{
          "member_id" => Views.uuid(),
          "package_id" => Views.uuid(),
          "status" => %{"type" => "string"}
        },
        "required" => ["member_id", "package_id", "status"]
      },
      examples: [
        %{
          input: %{
            "member_id" => "6a1c3b52-8d0e-4c5c-9d4f-2f5a3e8b9c10",
            "package_id" => "2c4e6a8b-0d1f-4a3b-8c5d-7e9f1a2b3c4d"
          },
          output: %{}
        }
      ]
    }
  end

  @impl true
  def preview(context, input) do
    case Finance.get_package(context, input["package_id"]) do
      nil ->
        {:error, :not_found}

      package ->
        {:ok,
         %{
           "would" => "give the package",
           "package" => Views.package(package, "EUR"),
           "member_id" => input["member_id"]
         }}
    end
  end

  @impl true
  def execute(context, input) do
    params =
      %{"package_id" => input["package_id"]}
      |> then(&if(input["starts_on"], do: Map.put(&1, "starts_on", input["starts_on"]), else: &1))

    with {:ok, _result} <- AssignFinanceMemberPackage.call(context, input["member_id"], params) do
      {:ok,
       %{
         "member_id" => input["member_id"],
         "package_id" => input["package_id"],
         "status" => "assigned"
       }}
    end
  end
end
