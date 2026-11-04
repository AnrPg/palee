defmodule PaleeWeb.TrainsWithPaleeTest do
  @moduledoc """
  ADR-463: staff say once whether they also train with Palee; `nil` means
  never asked and reads as "trains".
  """

  use PaleeWeb.ConnCase, async: true

  import Palee.TestFixtures

  alias Palee.Identity

  defp put_json(conn, user, body) do
    conn
    |> put_bearer_token(user)
    |> put_req_header("content-type", "application/json")
    |> put("/api/me/trains-with-palee", Jason.encode!(body))
  end

  defp me(conn, user) do
    conn
    |> recycle()
    |> put_bearer_token(user)
    |> get("/api/auth/me")
    |> json_response(200)
  end

  test "/auth/me says null until the person answers", %{conn: conn} do
    user = user_fixture()

    assert %{"trains_with_palee" => nil} = me(conn, user)
  end

  test "the answer is stored on the profile and shown by /auth/me", %{conn: conn} do
    user = user_fixture()

    assert %{"trains_with_palee" => false} =
             conn |> put_json(user, %{trains_with_palee: false}) |> json_response(200)

    assert Identity.find_by_id(user.id).trains_with_palee == false
    assert %{"trains_with_palee" => false} = me(conn, user)

    assert %{"trains_with_palee" => true} =
             conn |> recycle() |> put_json(user, %{trains_with_palee: true}) |> json_response(200)

    assert Identity.find_by_id(user.id).trains_with_palee == true
  end

  test "anything but yes or no is refused and nothing changes", %{conn: conn} do
    user = user_fixture()

    conn |> put_json(user, %{trains_with_palee: "maybe"}) |> json_response(422)
    conn |> recycle() |> put_json(user, %{}) |> json_response(422)

    assert Identity.find_by_id(user.id).trains_with_palee == nil
  end

  test "the application service refuses a non-boolean" do
    user = user_fixture()

    assert {:error, :invalid_trains_with_palee} =
             Palee.Application.SetTrainsWithPalee.call(user, nil)
  end

  test "needs a signed-in person", %{conn: conn} do
    conn
    |> put_req_header("content-type", "application/json")
    |> put("/api/me/trains-with-palee", Jason.encode!(%{trains_with_palee: false}))
    |> json_response(401)
  end
end
