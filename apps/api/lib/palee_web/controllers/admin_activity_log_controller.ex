defmodule PaleeWeb.AdminActivityLogController do
  @moduledoc """
  ADR-760: the box's «Αρχείο ενεργειών» (Διαχείριση › Αρχείο ενεργειών and
  a member profile's «Ιστορικό» tab, which passes `person_id`), and its CSV.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.ActivityLog
  alias Palee.ActivityLog.Domain.Visibility
  alias PaleeWeb.Schemas.ActivityLog, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Activity log"])
  security([%{"bearerAuth" => []}])

  @filters [
    %Parameter{
      name: :areas,
      in: :query,
      description: "Comma list of areas (default: every area the reader may see)",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :person_id,
      in: :query,
      description: "Only rows about this person",
      schema: %Schema{type: :string, format: :uuid}
    },
    %Parameter{
      name: :actor_id,
      in: :query,
      description: "Only rows by this staff member",
      schema: %Schema{type: :string, format: :uuid}
    },
    %Parameter{
      name: :actions,
      in: :query,
      description: "Comma list of action keys",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :from,
      in: :query,
      description: "First day (the box's own day)",
      schema: %Schema{type: :string, format: :date}
    },
    %Parameter{
      name: :to,
      in: :query,
      description: "Last day, included (the box's own day)",
      schema: %Schema{type: :string, format: :date}
    },
    %Parameter{
      name: :q,
      in: :query,
      description: "Text in the reason, the subject or a person's name",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :sensitive,
      in: :query,
      description: "Only the sensitive actions (the owner's daily summary links here, 12B)",
      schema: %Schema{type: :boolean}
    }
  ]

  @page [
    %Parameter{name: :cursor, in: :query, schema: %Schema{type: :string}},
    %Parameter{
      name: :limit,
      in: :query,
      schema: %Schema{type: :integer, minimum: 1, maximum: 200}
    }
  ]

  operation(:index,
    summary: "Who on the staff changed what, when, to whom and why, newest first",
    parameters: @filters ++ @page,
    responses: [
      ok: {"Activity log", "application/json", S.page()},
      forbidden: {"No area of the log for this role", "application/json", %Schema{type: :object}}
    ]
  )

  def index(conn, params) do
    context = conn.assigns.tenant_context
    params = Map.update(params, "limit", nil, &min(to_integer(&1), 200))

    with {:ok, page} <- ActivityLog.list(context, params) do
      readable = Visibility.readable(context.capabilities)

      json(
        conn,
        Map.merge(page, %{
          can_export: Visibility.can_export?(context.capabilities),
          areas: Enum.map(readable.all ++ readable.own, &Atom.to_string/1)
        })
      )
    end
  end

  operation(:export,
    summary: "The activity log as CSV, with the same filters (owner, admins, accountant)",
    parameters: @filters,
    responses: [
      ok: {"CSV", "text/csv", %Schema{type: :string}},
      forbidden: {"Not allowed", "application/json", %Schema{type: :object}}
    ]
  )

  def export(conn, params) do
    context = conn.assigns.tenant_context

    with {:ok, csv} <- ActivityLog.export_csv(context, params) do
      day = Date.to_iso8601(Palee.Organizations.local_today(context.organization_id))

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="activity-log-#{day}.csv")
      )
      |> send_resp(200, csv)
    end
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _rest} -> n
      :error -> 50
    end
  end

  defp to_integer(_value), do: 50
end
