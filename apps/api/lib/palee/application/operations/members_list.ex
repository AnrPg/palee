defmodule Palee.Application.Operations.MembersList do
  @moduledoc "ADR-378 `members.list`: the box's people (wraps `ListAdminUsers`)."

  @behaviour Palee.Operations.Operation

  alias Palee.Application.ListAdminUsers
  alias Palee.Application.Operations.Views
  alias Palee.{Identity, Organizations}

  @impl true
  def spec do
    %{
      name: "members.list",
      kind: :query,
      summary: "List the box's members",
      description:
        "Active people of the box, by name. Filter `role=client` for members and athletes, " <>
          "`role=staff` for the team. Use it to sync people into another system; for one " <>
          "person use members.get. Email is included only when the key's staff member may " <>
          "see contact details.",
      capability: [:view_directory],
      scope: "members:read",
      risk: :read,
      data_classes: [:personal],
      http: %{method: :get, path: "/members"},
      input:
        Views.page_input(%{
          "role" => %{
            "type" => "string",
            "enum" => ["client", "staff"],
            "x-enum-descriptions" => %{
              "client" => "Members and athletes.",
              "staff" => "Owners, admins, coaches, front desk."
            }
          }
        }),
      output: Views.page(Views.member_schema()),
      examples: [%{input: %{"limit" => 10, "role" => "client"}, output: %{}}]
    }
  end

  @impl true
  def execute(context, input) do
    with {:ok, offset} <- Views.decode_cursor(input["cursor"]),
         params = %{"limit" => input["limit"], "offset" => offset, "role" => input["role"]},
         {:ok, %{users: users, meta: meta}} <- ListAdminUsers.call(params, context) do
      email? = Organizations.can?(context, :view_billing_contacts)

      accounts =
        if email?,
          do: users |> Enum.map(& &1.id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1}),
          else: %{}

      data =
        Enum.map(users, fn user ->
          account = Map.get(accounts, user.id, %{})
          Views.member(Map.merge(user, %{email: Map.get(account, :email)}), user.roles, email?)
        end)

      {:ok,
       %{"data" => data, "next_cursor" => Views.next_cursor(offset, input["limit"], meta.total)}}
    end
  end
end
