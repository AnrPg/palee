defmodule PaleeWeb.WatchControllerTest do
  @moduledoc "ADR-375: pairing watches (Εγώ › Συνδεδεμένες συσκευές › «Ρολόι»)."

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  test "pair, refresh, list and unpair a watch; another person sees none", %{conn: conn} do
    member = user_fixture()
    other = user_fixture()

    assert %{
             "contract" => %{"version" => 1, "platforms" => ["apple_watch", "wear_os"]},
             "watches" => []
           } =
             conn |> as(member) |> get("/api/me/devices/watches") |> json_response(200)

    assert %{
             "watch" => %{
               "platform" => "wear_os",
               "settings" => settings,
               "needs_upgrade" => false
             }
           } =
             conn
             |> as(member)
             |> send_json(:put, "/api/me/devices/watches/wear_os", %{
               contract_version: 1,
               device_name: "Pixel Watch",
               app_version: "3.2.0",
               settings: %{haptics: false}
             })
             |> json_response(200)

    assert settings["haptics"] == false
    assert settings["show_heart_rate"] == true

    assert %{"watch" => %{"settings" => %{"haptics" => false, "max_hr" => 190}}} =
             conn
             |> as(member)
             |> send_json(:put, "/api/me/devices/watches/wear_os", %{
               contract_version: 1,
               settings: %{max_hr: 190}
             })
             |> json_response(200)

    assert %{"code" => "watch_upgrade_required"} =
             conn
             |> as(member)
             |> send_json(:put, "/api/me/devices/watches/apple_watch", %{contract_version: 2})
             |> json_response(426)

    assert %{"errors" => [%{"source" => %{"pointer" => "/settings/max_hr"}}]} =
             conn
             |> as(member)
             |> send_json(:put, "/api/me/devices/watches/apple_watch", %{
               contract_version: 1,
               settings: %{max_hr: 100}
             })
             |> json_response(422)

    assert %{"watches" => [%{"platform" => "wear_os"}]} =
             conn |> as(member) |> get("/api/me/devices/watches") |> json_response(200)

    assert %{"watches" => []} =
             conn |> as(other) |> get("/api/me/devices/watches") |> json_response(200)

    assert conn |> as(other) |> delete("/api/me/devices/watches/wear_os") |> json_response(404)
    assert conn |> as(member) |> delete("/api/me/devices/watches/wear_os") |> response(204)
    assert conn |> as(member) |> delete("/api/me/devices/watches/wear_os") |> json_response(404)
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end
end
