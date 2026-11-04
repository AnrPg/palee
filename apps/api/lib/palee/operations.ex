defmodule Palee.Operations do
  @moduledoc """
  The operation registry (ADR-300, first step in ADR-378). Operation modules
  are listed in `config :palee, :operations`; this module finds them, checks
  their specs and lists their REST routes. Running one (policy, validation,
  idempotency) is `Palee.Application.Operations.Runner`.

  The registry is plain data over plain behaviours (ADR-043: no macros).
  """

  alias Palee.Operations.Domain.JsonSchema

  @kinds [:query, :command]
  @risks [:read, :write_reversible, :write_irreversible, :outward, :money]
  @data_classes [:personal, :health, :financial, :user_generated]
  @methods [:get, :post, :delete, :patch]

  def risks, do: @risks
  def data_classes, do: @data_classes

  @doc "Every registered operation module."
  def modules, do: Application.get_env(:palee, :operations, [])

  @doc "Every spec, by name order."
  def specs, do: modules() |> Enum.map(&spec_of/1) |> Enum.sort_by(&{&1.name, &1.version})

  @doc "`{:ok, module, spec}` for a name (latest version), or `{:error, :unknown_operation}`."
  def fetch(name) do
    case Enum.filter(modules(), &(spec_of(&1).name == name)) do
      [] ->
        {:error, :unknown_operation}

      modules ->
        module = Enum.max_by(modules, &spec_of(&1).version)
        {:ok, module, spec_of(module)}
    end
  end

  @doc "REST routes: `[{method, phoenix_path, name}]`, e.g. `{:get, \"/members/:id\", \"members.get\"}`."
  def routes do
    for spec <- specs(), http = spec[:http], is_map(http) do
      {http.method, phoenix_path(http.path), spec.name}
    end
  end

  @doc "`/members/{id}` (OpenAPI) as `/members/:id` (Phoenix)."
  def phoenix_path(path), do: Regex.replace(~r/\{([a-z_]+)\}/, path, ":\\1")

  @doc "The spec of a module, with `version` defaulting to 1."
  def spec_of(module), do: Map.put_new(module.spec(), :version, 1)

  @doc """
  ADR-300's contract for one module: `:ok` or `{:error, problems}`.
  Checks the schemas, the declared kind, risk, data classes and route,
  that commands have a preview, and that examples pass their schemas.
  """
  def contract(module) do
    spec = spec_of(module)

    problems =
      []
      |> need(is_binary(spec[:name]) and spec.name =~ ~r/\A[a-z_]+\.[a-z_]+\z/, "name")
      |> need(spec[:kind] in @kinds, "kind")
      |> need(spec[:risk] in @risks, "risk")
      |> need(
        is_list(spec[:data_classes]) and Enum.all?(spec.data_classes, &(&1 in @data_classes)),
        "data_classes"
      )
      |> need(is_list(spec[:capability]) and spec.capability != [], "capability")
      |> need(is_binary(spec[:scope]), "scope")
      |> need(
        is_binary(spec[:summary]) and is_binary(spec[:description]),
        "summary and description"
      )
      |> need(
        spec[:kind] == :query or function_exported?(module, :preview, 2),
        "commands need preview/2"
      )
      |> need(spec[:kind] == :query or spec[:risk] != :read, "commands must declare a write risk")
      |> need(match?(%{method: m, path: "/" <> _} when m in @methods, spec[:http]), "http")
      |> schema_problems("input", spec[:input])
      |> schema_problems("output", spec[:output])
      |> example_problems(spec)

    if problems == [], do: :ok, else: {:error, Enum.reverse(problems)}
  end

  defp need(problems, true, _what), do: problems
  defp need(problems, _false, what), do: [what | problems]

  defp schema_problems(problems, label, schema) when is_map(schema) do
    case JsonSchema.contract_check(schema) do
      :ok -> problems
      {:error, found} -> Enum.map(found, &"#{label} #{&1}") ++ problems
    end
  end

  defp schema_problems(problems, label, _schema), do: ["#{label} schema missing" | problems]

  defp example_problems(problems, %{examples: [_ | _] = examples, input: input}) do
    Enum.reduce(examples, problems, fn example, acc ->
      case JsonSchema.cast(input, example.input) do
        {:ok, _cast} -> acc
        {:error, errors} -> ["example input fails: #{inspect(errors)}" | acc]
      end
    end)
  end

  defp example_problems(problems, _spec), do: ["examples missing" | problems]

  @doc "Validates and casts input: `{:ok, input}` or `{:error, {:invalid_fields, errors}}`."
  def cast_input(spec, input) do
    case JsonSchema.cast(spec.input, input) do
      {:ok, cast} -> {:ok, cast || %{}}
      {:error, errors} -> {:error, {:invalid_fields, errors}}
    end
  end
end
