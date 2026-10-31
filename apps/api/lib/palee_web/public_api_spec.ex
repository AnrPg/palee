defmodule PaleeWeb.PublicApiSpec do
  @moduledoc """
  The public API v1's OpenAPI 3.1 document (ADR-378), generated from the
  operation registry (ADR-300): every path, parameter, body and answer
  comes from an operation's spec, so the document cannot drift from what
  runs. Webhook events are in OpenAPI 3.1's `webhooks`.

  Served at `GET /api/public/v1/openapi.json`, without a key, for Zapier,
  Make and anyone building on Palee.
  """

  alias Palee.Application.Integrations.PublicApi
  alias Palee.Integrations.Domain.{PublicEvents, Scopes}

  @prefix "/api/public/v1"

  def prefix, do: @prefix

  @doc "The document as a JSON-ready map."
  def document(base_url \\ Palee.Application.PublicURL.base_url()) do
    specs = PublicApi.specs()

    %{
      "openapi" => "3.1.0",
      "jsonSchemaDialect" => "https://json-schema.org/draft/2020-12/schema",
      "info" => %{
        "title" => "Palee public API",
        "version" => "v1",
        "description" => description()
      },
      "servers" => [%{"url" => String.trim_trailing(base_url, "/") <> @prefix}],
      "security" => [%{"apiKey" => []}],
      "tags" => specs |> Enum.map(&tag/1) |> Enum.uniq() |> Enum.sort() |> Enum.map(&%{"name" => &1}),
      "paths" => paths(specs),
      "webhooks" => webhooks(),
      "components" => %{
        "securitySchemes" => %{
          "apiKey" => %{
            "type" => "http",
            "scheme" => "bearer",
            "description" =>
              "A box's API key (Settings › Connections), `palee_live_…`. It acts for the " <>
                "staff member who made it, narrowed to its scopes: " <>
                Enum.join(Scopes.all(), ", ") <> "."
          }
        },
        "schemas" => %{"Problem" => problem()},
        "responses" => %{
          "Problem" => %{
            "description" => "Refused (RFC 9457). `code` is stable; `title` is English copy.",
            "content" => %{
              "application/problem+json" => %{"schema" => %{"$ref" => "#/components/schemas/Problem"}}
            }
          }
        }
      }
    }
  end

  defp description do
    """
    Read and write a box's members, classes, bookings and packages, and read its \
    payments. Every request carries `Authorization: Bearer <key>`.

    * **Idempotency.** Send `Idempotency-Key` with a command: the same key and body \
    within 24 hours answer the first result again (header `Idempotent-Replayed: true`) \
    without running twice; the same key with another body is refused.
    * **Preview.** `Palee-Preview: true` on a command answers what it would do and \
    writes nothing.
    * **Limits.** 120 requests per minute per key (`429 rate_limited`).
    * **Pages.** Lists answer `data` and `next_cursor`; pass it as `cursor`.
    * **Webhooks.** Subscribe with `POST /webhook-subscriptions`; each delivery is signed \
    in `Palee-Signature: t=<unix>,v1=<hex HMAC-SHA256 of "t.body">`.
    * **Times** are UTC ISO 8601, **money** integer cents with an ISO 4217 currency.
    """
  end

  defp tag(spec), do: spec.name |> String.split(".") |> hd()

  defp paths(specs) do
    specs
    |> Enum.group_by(& &1.http.path)
    |> Map.new(fn {path, specs} ->
      {path, Map.new(specs, &{Atom.to_string(&1.http.method), operation(&1)})}
    end)
  end

  defp operation(spec) do
    path_params = path_params(spec.http.path)
    {in_path, rest} = split_input(spec.input, path_params)
    body? = spec.http.method in [:post, :patch]
    status = spec.http |> Map.get(:status, 200) |> Integer.to_string()

    %{
      "operationId" => spec.name,
      "summary" => spec.summary,
      "description" => spec.description,
      "tags" => [tag(spec)],
      "x-palee-scope" => spec.scope,
      "x-palee-risk" => Atom.to_string(spec.risk),
      "x-palee-kind" => Atom.to_string(spec.kind),
      "parameters" =>
        Enum.map(in_path, &param(&1, "path", true)) ++
          if(body?, do: [], else: query_params(rest)) ++ header_params(spec),
      "responses" => %{
        status => %{
          "description" => spec.summary,
          "content" => %{"application/json" => %{"schema" => spec.output}}
        },
        "default" => %{"$ref" => "#/components/responses/Problem"}
      }
    }
    |> maybe_body(body?, rest)
  end

  defp maybe_body(operation, false, _schema), do: operation

  defp maybe_body(operation, true, schema) do
    Map.put(operation, "requestBody", %{
      "required" => true,
      "content" => %{"application/json" => %{"schema" => schema}}
    })
  end

  defp path_params(path),
    do: ~r/\{([a-z_]+)\}/ |> Regex.scan(path) |> Enum.map(fn [_all, name] -> name end)

  defp split_input(input, path_params) do
    properties = Map.get(input, "properties", %{})
    in_path = Enum.map(path_params, &{&1, Map.get(properties, &1, %{"type" => "string"})})

    rest =
      input
      |> Map.put("properties", Map.drop(properties, path_params))
      |> Map.put("required", (Map.get(input, "required", []) -- path_params) |> Enum.sort())

    {in_path, rest}
  end

  defp query_params(schema) do
    required = Map.get(schema, "required", [])

    schema
    |> Map.get("properties", %{})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&param(&1, "query", elem(&1, 0) in required))
  end

  defp param({name, schema}, location, required) do
    %{"name" => name, "in" => location, "required" => required, "schema" => schema}
    |> then(&if(schema["description"], do: Map.put(&1, "description", schema["description"]), else: &1))
  end

  defp header_params(%{kind: :command}) do
    [
      %{
        "name" => "Idempotency-Key",
        "in" => "header",
        "required" => false,
        "description" => "1–255 visible ASCII characters, e.g. a UUID; remembered 24 hours.",
        "schema" => %{"type" => "string", "maxLength" => 255}
      },
      %{
        "name" => "Palee-Preview",
        "in" => "header",
        "required" => false,
        "description" => "`true`: answer what the command would do, write nothing.",
        "schema" => %{"type" => "string", "enum" => ["true", "false"]}
      }
    ]
  end

  defp header_params(_query), do: []

  defp problem do
    %{
      "type" => "object",
      "properties" => %{
        "type" => %{"type" => "string", "description" => "`urn:palee:problem:<code>`"},
        "title" => %{"type" => "string"},
        "status" => %{"type" => "integer"},
        "code" => %{"type" => "string"},
        "params" => %{"type" => "object"},
        "errors" => %{"type" => "object", "description" => "Field → messages, for invalid input"}
      },
      "required" => ["code", "status", "title", "type"]
    }
  end

  defp webhooks do
    Map.new(PublicEvents.catalog(), fn event ->
      {event.type,
       %{
         "post" => %{
           "summary" => event.en,
           "description" =>
             "Needs the `#{event.scope}` scope to subscribe. Thin by design: ids only; read " <>
               "the object through the API for more.",
           "parameters" => [
             %{
               "name" => "Palee-Signature",
               "in" => "header",
               "required" => true,
               "schema" => %{"type" => "string"}
             }
           ],
           "requestBody" => %{
             "content" => %{"application/json" => %{"schema" => envelope(event.type)}}
           },
           "responses" => %{
             "2XX" => %{"description" => "Received; anything else is retried with backoff"}
           }
         }
       }}
    end)
  end

  defp envelope(type) do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string", "format" => "uuid", "description" => "Drop duplicates by it"},
        "type" => %{"const" => type},
        "api_version" => %{"const" => PublicEvents.api_version()},
        "created_at" => %{"type" => "string", "format" => "date-time"},
        "box_id" => %{"type" => "string", "format" => "uuid"},
        "data" => %{"type" => "object"}
      },
      "required" => ["api_version", "box_id", "created_at", "data", "id", "type"]
    }
  end
end
