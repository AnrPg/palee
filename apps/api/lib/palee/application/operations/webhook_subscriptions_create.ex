defmodule Palee.Application.Operations.WebhookSubscriptionsCreate do
  @moduledoc """
  ADR-379 `webhook_subscriptions.create`: a REST-hook subscription, what
  Zapier and Make call when a user turns a Palee trigger on. It lives as
  long as the key (revoking the key removes it).
  """

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Integrations

  @impl true
  def spec do
    %{
      name: "webhook_subscriptions.create",
      kind: :command,
      summary: "Subscribe a URL to events",
      description:
        "Palee posts each event to the URL, signed with the returned secret (Palee-Signature " <>
          "header). Each event type needs the read scope of its object. Zapier and Make call " <>
          "this when a trigger is turned on and webhook_subscriptions.delete when it is off.",
      capability: [:manage_settings],
      scope: "webhooks:write",
      risk: :write_reversible,
      data_classes: [],
      http: %{method: :post, path: "/webhook-subscriptions", status: 201},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "url" => %{"type" => "string", "format" => "uri", "maxLength" => 2000},
          "events" => %{
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 10,
            "items" => %{"type" => "string", "enum" => Palee.Integrations.Domain.PublicEvents.types()}
          }
        },
        "required" => ["events", "url"]
      },
      output: %{
        "type" => "object",
        "properties" => %{
          "id" => Views.uuid(),
          "url" => %{"type" => "string"},
          "events" => %{"type" => "array", "items" => %{"type" => "string"}},
          "secret" => %{"type" => "string", "description" => "Shown once. Verify signatures with it."}
        },
        "required" => ["events", "id", "secret", "url"]
      },
      examples: [
        %{input: %{"url" => "https://hooks.zapier.com/hooks/standard/1/abc", "events" => ["booking.created"]}, output: %{}}
      ]
    }
  end

  @impl true
  def preview(_context, input), do: {:ok, %{"would" => "subscribe", "url" => input["url"], "events" => input["events"]}}

  @impl true
  def execute(%{principal: %{kind: :api_key, api_key_id: key_id, scopes: scopes}} = context, input) do
    with {:ok, %{endpoint: endpoint, secret: secret}} <-
           Integrations.create_endpoint(
             context,
             %{url: input["url"], events: input["events"], description: "API subscription"},
             context.user_id,
             source: "api",
             api_key_id: key_id,
             scopes: scopes
           ) do
      {:ok, %{"id" => endpoint.id, "url" => endpoint.url, "events" => endpoint.events, "secret" => secret}}
    end
  end

  def execute(_context, _input), do: {:error, :api_key_required}
end
