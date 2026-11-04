defmodule Palee.Application.Operations.MembersGet do
  @moduledoc "ADR-378 `members.get`: one person of the box."

  @behaviour Palee.Operations.Operation

  alias Palee.Application.AuthorizeClientAccess
  alias Palee.Application.Operations.Views
  alias Palee.{Identity, Organizations}

  @impl true
  def spec do
    %{
      name: "members.get",
      kind: :query,
      summary: "Get one member",
      description:
        "A person of the box by id (the ids webhooks carry). Answers not_found for anyone who " <>
          "is not, or no longer, part of the box.",
      capability: [:view_directory],
      scope: "members:read",
      risk: :read,
      data_classes: [:personal],
      http: %{method: :get, path: "/members/{id}"},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"id" => Views.uuid()},
        "required" => ["id"]
      },
      output: Views.member_schema(),
      examples: [%{input: %{"id" => "6a1c3b52-8d0e-4c5c-9d4f-2f5a3e8b9c10"}, output: %{}}]
    }
  end

  @impl true
  def execute(context, %{"id" => id}) do
    roles = context |> Organizations.member_roles_by_user() |> Map.get(id)

    with %{roles: roles} <- roles,
         true <- visible?(context, id),
         %{} = account <- Identity.find_by_id(id) do
      {:ok, Views.member(account, roles, Organizations.can?(context, :view_billing_contacts))}
    else
      _missing -> {:error, :not_found}
    end
  end

  # A coach with `:own` directory scope sees only their own clients (ADR-100).
  defp visible?(context, id) do
    case AuthorizeClientAccess.client_ids(context, :view_directory) do
      :all -> true
      ids -> id in ids
    end
  end
end
