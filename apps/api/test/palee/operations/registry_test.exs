defmodule Palee.Operations.RegistryTest do
  @moduledoc "ADR-300/378: every registered operation keeps the registry's contract."

  use ExUnit.Case, async: true

  alias Palee.Operations
  alias Palee.Operations.Domain.JsonSchema

  test "every operation passes the contract" do
    assert length(Operations.modules()) >= 15

    for module <- Operations.modules() do
      assert Operations.contract(module) == :ok,
             "#{inspect(module)}: #{inspect(Operations.contract(module))}"
    end
  end

  test "names and routes are unique; payments are read-only" do
    specs = Operations.specs()
    names = Enum.map(specs, & &1.name)
    routes = Enum.map(Operations.routes(), fn {method, path, _name} -> {method, path} end)

    assert names == Enum.uniq(names)
    assert routes == Enum.uniq(routes)

    for spec <- specs, String.starts_with?(spec.name, "payments.") do
      assert spec.kind == :query and spec.risk == :read
    end

    for spec <- specs, spec.kind == :command do
      refute String.ends_with?(spec.scope, ":read"), spec.name
    end
  end

  test "routes use Phoenix path parameters" do
    assert {:get, "/members/:id", "members.get"} in Operations.routes()

    assert Operations.phoenix_path("/classes/{class_id}/bookings") ==
             "/classes/:class_id/bookings"

    assert {:error, :unknown_operation} = Operations.fetch("members.delete")
  end

  describe "JSON Schema cast" do
    @schema %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "id" => %{"type" => "string", "format" => "uuid"},
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 50, "default" => 25},
        "role" => %{"type" => "string", "enum" => ["client", "staff"]},
        "at" => %{"type" => ["string", "null"], "format" => "date-time"},
        "tags" => %{"type" => "array", "items" => %{"type" => "string"}, "maxItems" => 2}
      },
      "required" => ["id"]
    }

    test "casts query strings, fills defaults and keeps only known properties" do
      id = Ecto.UUID.generate()

      assert {:ok, %{"id" => ^id, "limit" => 10, "role" => "staff", "at" => nil}} =
               JsonSchema.cast(@schema, %{
                 "id" => id,
                 "limit" => "10",
                 "role" => "staff",
                 "at" => nil
               })

      assert {:ok, %{"limit" => 25}} = JsonSchema.cast(@schema, %{"id" => id})
    end

    test "reports every field's problem" do
      assert {:error, errors} =
               JsonSchema.cast(@schema, %{
                 "limit" => "500",
                 "role" => "owner",
                 "at" => "yesterday",
                 "tags" => ["a", "b", "c"],
                 "extra" => 1
               })

      assert Map.keys(errors) |> Enum.sort() == ~w(at extra id limit role tags)
    end

    test "contract_check refuses unsorted required lists and unsupported keywords" do
      assert :ok = JsonSchema.contract_check(@schema)

      assert {:error, _problems} =
               JsonSchema.contract_check(%{@schema | "required" => ["b", "a"]})

      assert {:error, _problems} = JsonSchema.contract_check(Map.put(@schema, "oneOf", []))
    end
  end
end
