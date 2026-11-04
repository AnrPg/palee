defmodule PaleeWeb.Plugs.RequireWodAccess do
  @moduledoc """
  ADR-551: refuses a workout read with 403 `finance_entitlement_blocked` or
  `finance_entitlement_inactive` when the caller's access has closed
  (`Palee.Application.AuthorizeWodAccess`). Used per action in the
  controllers that hand out workout content to members.
  """

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.AuthorizeWodAccess

  def init(opts), do: opts

  def call(conn, _opts) do
    user = GuardianPlug.current_resource(conn)

    case AuthorizeWodAccess.call(conn.assigns[:tenant_context], user && user.id) do
      :ok -> conn
      error -> conn |> PaleeWeb.FallbackController.call(error) |> Plug.Conn.halt()
    end
  end
end
