defmodule PaleeWeb.Plugs.RecordActivity do
  @moduledoc """
  ADR-760: writes the «Αρχείο ενεργειών» row of a staff request that
  changed something: a POST, PUT, PATCH or DELETE that answered 2xx, whose
  route `PaleeWeb.RouteActivity` names (3A). It runs just before the
  response leaves, after the change itself succeeded.

  What the row holds: the key, the person it is about (`:user_id` in the
  path, `:id` under `/users/` or `/finance/members/`, or `user_id` in the
  body), the ids the path named, the reason the request carried and whether
  it is shared with the member (`reason_shared`), and whatever the use case
  added with `Palee.ActivityLog.note/1`. A replayed idempotent request
  (`"replayed": true`) is not recorded twice. A row that cannot be written
  is logged and counted (`[:palee, :activity_log, :failed]`); the response
  is not changed.
  """

  import Plug.Conn

  alias Palee.ActivityLog
  alias PaleeWeb.RouteActivity

  require Logger

  @methods ~w(POST PUT PATCH DELETE)
  @reason_fields ~w(reason status_reason cancel_reason decline_reason end_reason)
  @person_paths [
    ~r{^/api/org/[^/]+/admin/users/(?<id>[^/]+)},
    ~r{^/api/org/[^/]+/admin/finance/members/(?<id>[^/]+)},
    ~r{^/api/org/[^/]+/admin/wellbeing/users/(?<id>[^/]+)}
  ]

  def init(opts), do: opts

  def call(%{method: method} = conn, _opts) when method in @methods do
    ActivityLog.clear_notes()
    register_before_send(conn, &record/1)
  end

  def call(conn, _opts), do: conn

  defp record(%{status: status} = conn) when status in 200..299 do
    notes = ActivityLog.take_notes()

    with false <- Map.get(notes, :skip, false),
         false <- replayed?(conn),
         %{} = context <- conn.assigns[:tenant_context],
         key when is_binary(key) <- notes[:action] || route_key(conn) do
      write(context, key, conn, notes)
    end

    conn
  rescue
    error ->
      Logger.error("activity_log_plug_failed #{Exception.format(:error, error, __STACKTRACE__)}")
      conn
  end

  defp record(conn) do
    ActivityLog.take_notes()
    conn
  end

  defp route_key(conn) do
    RouteActivity.key(
      conn.private[:phoenix_controller],
      conn.private[:phoenix_action],
      conn.path_params
    )
  end

  defp write(context, key, conn, notes) do
    body = body(conn)

    ActivityLog.record(context, %{
      action: key,
      person_user_id: notes[:person_user_id] || person(conn, body),
      subject: Map.merge(subject(conn), Map.get(notes, :subject, %{})),
      subject_label: notes[:subject_label],
      details: Map.get(notes, :details, %{}),
      reason: Map.get_lazy(notes, :reason, fn -> reason(body) end),
      reason_shared: Map.get_lazy(notes, :reason_shared, fn -> body["reason_shared"] == true end),
      request_id: request_id(conn)
    })
  end

  defp replayed?(%{resp_body: body}) when is_binary(body),
    do: String.contains?(body, ~s("replayed":true))

  defp replayed?(%{resp_body: body}) when is_list(body),
    do: body |> IO.iodata_to_binary() |> String.contains?(~s("replayed":true))

  defp replayed?(_conn), do: false

  # CastAndValidate (OpenApiSpex) leaves the body cast, with atom keys (and
  # sometimes as a struct): read it the same way either way.
  defp body(%{body_params: %{} = params}) do
    params
    |> then(fn map -> if is_struct(map), do: Map.from_struct(map), else: map end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp body(_conn), do: %{}

  defp person(conn, body) do
    path_person(conn) || uuid(body["user_id"])
  end

  defp path_person(conn) do
    case uuid(conn.path_params["user_id"] || conn.path_params[:user_id]) do
      nil ->
        Enum.find_value(@person_paths, fn pattern ->
          case Regex.named_captures(pattern, conn.request_path) do
            %{"id" => id} -> uuid(id)
            nil -> nil
          end
        end)

      id ->
        id
    end
  end

  defp subject(conn) do
    conn.path_params
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.drop(["organization_slug"])
    |> Map.new(fn {key, value} -> {key, to_string(value)} end)
  end

  defp reason(body) do
    Enum.find_value(@reason_fields, fn field ->
      case body[field] do
        text when is_binary(text) ->
          case String.trim(text) do
            "" -> nil
            trimmed -> String.slice(trimmed, 0, Palee.ActivityLog.Entry.max_reason())
          end

        _other ->
          nil
      end
    end)
  end

  defp request_id(conn), do: conn |> get_resp_header("x-request-id") |> List.first()

  defp uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp uuid(_value), do: nil
end
