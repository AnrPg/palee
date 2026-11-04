defmodule Palee.Application.Operations.WebhookSubscriptionsDelete do
  @moduledoc "ADR-379 `webhook_subscriptions.delete`: the REST-hook unsubscribe of the same key."

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Integrations

  @impl true
  def spec do
    %{
      name: "webhook_subscriptions.delete",
      kind: :command,
      summary: "Remove a subscription",
      description: "Stops sending events to a subscription this key made. Others are not found.",
      capability: [:manage_settings],
      scope: "webhooks:write",
      risk: :write_reversible,
      data_classes: [],
      http: %{method: :delete, path: "/webhook-subscriptions/{id}"},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"id" => Views.uuid()},
        "required" => ["id"]
      },
      output: %{
        "type" => "object",
        "properties" => %{"deleted" => %{"type" => "boolean"}},
        "required" => ["deleted"]
      },
      examples: [%{input: %{"id" => "9b2f4d6e-1a3c-4e5f-8a7b-6c5d4e3f2a1b"}, output: %{}}]
    }
  end

  @impl true
  def preview(_context, %{"id" => id}),
    do: {:ok, %{"would" => "remove the subscription", "id" => id}}

  @impl true
  def execute(%{principal: %{kind: :api_key, api_key_id: key_id}} = context, %{"id" => id}) do
    with :ok <- Integrations.delete_key_endpoint(context, key_id, id),
         do: {:ok, %{"deleted" => true}}
  end

  def execute(_context, _input), do: {:error, :api_key_required}
end
