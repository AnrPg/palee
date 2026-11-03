defmodule Palee.Application.Integrations.PublicApi do
  @moduledoc """
  The public API v1 (ADR-378): who a key is and running its operations.

  A key acts **for the staff member who made it** (ADR-301's delegated
  principal, without an agent): each request rebuilds that person's tenant
  context as of now and narrows it to the key's scopes. A key whose person
  left the box, lost the needed role or was deleted stops working at once,
  with no token to wait out.
  """

  alias Palee.Application.Operations.Runner
  alias Palee.{Identity, Integrations, Operations, Organizations}

  @doc """
  `{:ok, context}` for a valid bearer token, or `{:error,
  :invalid_api_key}`. The context is the key holder's, with `principal`
  `%{kind: :api_key, api_key_id, name, prefix, scopes, on_behalf_of}`.
  """
  def authenticate(token, request_metadata \\ %{}, now \\ DateTime.utc_now()) do
    with {:ok, %{organization_id: organization_id, key: key}} <-
           Integrations.authenticate(token, now),
         user_id when is_binary(user_id) <- key.created_by_id,
         %{} = account <- Identity.find_by_id(user_id),
         {:ok, context} <-
           Organizations.resolve_tenant_context_by_id(account, organization_id, request_metadata) do
      {:ok,
       %{
         context
         | principal: %{
             kind: :api_key,
             api_key_id: key.id,
             name: key.name,
             prefix: key.prefix,
             scopes: key.scopes,
             on_behalf_of: user_id
           }
       }}
    else
      _invalid -> {:error, :invalid_api_key}
    end
  end

  @doc "Runs `name` for the key: `{:ok, status, body}` (`:replayed` as a 4th element) or an error."
  def run(context, name, input, opts \\ []), do: Runner.run(context, name, input, opts)

  @doc "REST routes of the registry (the router builds them at compile time)."
  def routes, do: Operations.routes()

  @doc "Every registered spec, for the OpenAPI document."
  def specs, do: Operations.specs()
end
