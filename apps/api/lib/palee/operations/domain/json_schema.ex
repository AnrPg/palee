defmodule Palee.Operations.Domain.JsonSchema do
  @moduledoc """
  Validates and casts an operation's input against its JSON Schema
  (ADR-300, ADR-378). One schema serves validation, the OpenAPI 3.1
  document (which is JSON Schema 2020-12) and, in v4, MCP and LLM tools.

  The supported subset is what operation specs use: `type` (one type or a
  list with `"null"`), `properties`, `required`, `additionalProperties:
  false`, `enum`, `format` (`uuid`, `date-time`, `date`, `email`, `uri`),
  `minLength`/`maxLength`, `minimum`/`maximum`, `items`,
  `minItems`/`maxItems`, `default`. Query strings are coerced (`"20"` → 20,
  `"true"` → true).

  `cast/2` answers `{:ok, value}` holding only the schema's own properties
  (string keys), or `{:error, errors}` with `%{"field.path" => [message]}`. A `contract_check/1` refuses schemas
  that use anything outside the subset, so a spec can't silently promise
  more than is enforced.
  """

  @keywords ~w(type properties required additionalProperties enum format minLength maxLength
               minimum maximum items minItems maxItems default description examples
               x-enum-descriptions readOnly title)
  @formats ~w(uuid date-time date email uri)
  @email ~r/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  @spec cast(map(), term()) :: {:ok, term()} | {:error, %{String.t() => [String.t()]}}
  def cast(schema, value) do
    case cast_at(schema, value, []) do
      {:ok, value, []} -> {:ok, value}
      {:ok, _value, errors} -> {:error, group(errors)}
    end
  end

  # -- casting

  defp cast_at(schema, nil, path) do
    cond do
      Map.has_key?(schema, "default") -> cast_at(schema, schema["default"], path)
      nullable?(schema) -> {:ok, nil, []}
      true -> {:ok, nil, [{path, "is required"}]}
    end
  end

  defp cast_at(schema, value, path) do
    case main_type(schema) do
      "object" -> object(schema, value, path)
      "array" -> array(schema, value, path)
      "string" -> string(schema, value, path)
      "integer" -> integer(schema, value, path)
      "boolean" -> boolean(value, path)
      nil -> {:ok, value, []}
    end
  end

  defp object(schema, value, path) when is_map(value) do
    properties = Map.get(schema, "properties", %{})
    required = Map.get(schema, "required", [])
    given = Map.new(value, fn {key, item} -> {to_string(key), item} end)

    unknown =
      if schema["additionalProperties"] == false,
        do: for(key <- Map.keys(given), not Map.has_key?(properties, key), do: {path ++ [key], "is not allowed"}),
        else: []

    {result, errors} =
      Enum.reduce(properties, {%{}, unknown}, fn {name, property}, {acc, errors} ->
        case Map.fetch(given, name) do
          :error ->
            cond do
              name in required -> {acc, [{path ++ [name], "is required"} | errors]}
              Map.has_key?(property, "default") -> {Map.put(acc, name, property["default"]), errors}
              true -> {acc, errors}
            end

          {:ok, item} ->
            {:ok, cast, item_errors} = cast_at(property, item, path ++ [name])
            {Map.put(acc, name, cast), item_errors ++ errors}
        end
      end)

    {:ok, result, errors}
  end

  defp object(_schema, _value, path), do: {:ok, nil, [{path, "must be an object"}]}

  defp array(schema, value, path) when is_list(value) do
    items = Map.get(schema, "items", %{})

    {values, errors} =
      value
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {item, index}, {acc, errors} ->
        {:ok, cast, item_errors} = cast_at(items, item, path ++ [Integer.to_string(index)])
        {[cast | acc], item_errors ++ errors}
      end)

    values = Enum.reverse(values)
    count = length(values)

    errors =
      errors
      |> check(schema["minItems"] && count < schema["minItems"], path, "has too few items")
      |> check(schema["maxItems"] && count > schema["maxItems"], path, "has too many items")

    {:ok, values, errors}
  end

  defp array(schema, value, path) when is_binary(value),
    do: array(schema, String.split(value, ",", trim: true), path)

  defp array(_schema, _value, path), do: {:ok, nil, [{path, "must be a list"}]}

  defp string(schema, value, path) when is_binary(value) do
    length = String.length(value)

    errors =
      []
      |> check(schema["enum"] && value not in schema["enum"], path, "is not one of the allowed values")
      |> check(schema["minLength"] && length < schema["minLength"], path, "is too short")
      |> check(schema["maxLength"] && length > schema["maxLength"], path, "is too long")
      |> check(not format?(schema["format"], value), path, "is not a valid #{schema["format"]}")

    {:ok, value, errors}
  end

  defp string(_schema, _value, path), do: {:ok, nil, [{path, "must be a string"}]}

  defp integer(schema, value, path) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> integer(schema, int, path)
      _invalid -> {:ok, nil, [{path, "must be an integer"}]}
    end
  end

  defp integer(schema, value, path) when is_integer(value) do
    errors =
      []
      |> check(schema["minimum"] && value < schema["minimum"], path, "is too small")
      |> check(schema["maximum"] && value > schema["maximum"], path, "is too large")

    {:ok, value, errors}
  end

  defp integer(_schema, _value, path), do: {:ok, nil, [{path, "must be an integer"}]}

  defp boolean(value, _path) when is_boolean(value), do: {:ok, value, []}
  defp boolean("true", _path), do: {:ok, true, []}
  defp boolean("false", _path), do: {:ok, false, []}
  defp boolean(_value, path), do: {:ok, nil, [{path, "must be true or false"}]}

  defp check(errors, condition, _path, _message) when condition in [nil, false], do: errors
  defp check(errors, _condition, path, message), do: [{path, message} | errors]

  defp format?(nil, _value), do: true
  defp format?("uuid", value), do: match?({:ok, _uuid}, Ecto.UUID.cast(value))
  defp format?("date", value), do: match?({:ok, _date}, Date.from_iso8601(value))
  defp format?("date-time", value), do: match?({:ok, _at, _offset}, DateTime.from_iso8601(value))
  defp format?("email", value), do: Regex.match?(@email, value) and String.length(value) <= 254

  defp format?("uri", value) do
    match?(%URI{scheme: scheme, host: host} when scheme in ["https", "http"] and is_binary(host), URI.parse(value))
  end

  defp main_type(%{"type" => types}) when is_list(types), do: Enum.find(types, &(&1 != "null"))
  defp main_type(%{"type" => type}), do: type
  defp main_type(%{"properties" => _properties}), do: "object"
  defp main_type(_schema), do: nil

  defp nullable?(%{"type" => types}) when is_list(types), do: "null" in types
  defp nullable?(_schema), do: false

  defp group(errors) do
    errors
    |> Enum.reverse()
    |> Enum.group_by(fn {path, _message} -> if path == [], do: "body", else: Enum.join(path, ".") end, &elem(&1, 1))
  end

  # -- the contract

  @doc """
  `:ok` when the schema uses only the supported subset (and its `required`
  names exist and are sorted), otherwise `{:error, reasons}`.
  """
  def contract_check(schema), do: schema |> problems([]) |> then(&if(&1 == [], do: :ok, else: {:error, &1}))

  defp problems(schema, path) when is_map(schema) do
    unknown =
      for key <- Map.keys(schema), key not in @keywords, do: "#{Enum.join(path, ".")}: unknown keyword #{key}"

    format =
      if schema["format"] && schema["format"] not in @formats,
        do: ["#{Enum.join(path, ".")}: unsupported format #{schema["format"]}"],
        else: []

    required = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})

    required_problems =
      cond do
        required != Enum.sort(required) -> ["#{Enum.join(path, ".")}: required is not sorted"]
        Enum.any?(required, &(not Map.has_key?(properties, &1))) -> ["#{Enum.join(path, ".")}: required names a missing property"]
        true -> []
      end

    nested =
      Enum.flat_map(properties, fn {name, property} -> problems(property, path ++ [name]) end) ++
        if(is_map(schema["items"]), do: problems(schema["items"], path ++ ["items"]), else: [])

    unknown ++ format ++ required_problems ++ nested
  end

  defp problems(_schema, path), do: ["#{Enum.join(path, ".")}: not a schema"]
end
