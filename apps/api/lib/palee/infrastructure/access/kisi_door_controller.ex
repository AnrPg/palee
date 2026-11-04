defmodule Palee.Infrastructure.Access.KisiDoorController do
  @moduledoc """
  A Kisi lock (ADR-381; https://docs.kisi.io/platform/cloud_unlocks/unlock_setup).

    * open: `POST https://api.kisi.io/locks/<lock_id>/unlock` with
      `Authorization: KISI-LOGIN <api_key>`; the time the lock stays open is
      the lock's own hardware setting. Kisi logs the unlock as the API key's
      owner; Palee's own access log names the member;
    * check: `GET https://api.kisi.io/locks/<lock_id>`;
    * events: a Kisi event webhook (`{"action": "unlock" | ..., "object_type":
      "Lock", "created_at"}`) posted to Palee's event URL.

  Kisi controllers keep working on their own when the internet drops (their
  own offline credentials); Palee's QR/NFC opening then waits for the
  network, and members use their Kisi credential or the desk.
  """

  @behaviour Palee.Access.Ports.DoorController

  alias Palee.Infrastructure.Access.Http

  @base "https://api.kisi.io"

  @impl true
  def unlock(controller, _seconds) do
    with {:ok, _response} <-
           Http.request(
             method: :post,
             url: "#{@base}/locks/#{controller.settings["lock_id"]}/unlock",
             headers: headers(controller),
             json: %{lock: %{proximity_proof: nil}}
           ),
         do: :ok
  end

  @impl true
  def check(controller) do
    with {:ok, _response} <-
           Http.request(
             method: :get,
             url: "#{@base}/locks/#{controller.settings["lock_id"]}",
             headers: headers(controller)
           ),
         do: :ok
  end

  @impl true
  def parse_event(_controller, %{"action" => action} = params) when is_binary(action) do
    occurred_at =
      case DateTime.from_iso8601(to_string(params["created_at"])) do
        {:ok, at, _offset} -> at
        _invalid -> nil
      end

    {:ok, [%{event: "kisi_" <> String.slice(action, 0, 70), occurred_at: occurred_at}]}
  end

  def parse_event(_controller, _params), do: {:error, :invalid_event}

  defp headers(controller),
    do: [{"authorization", "KISI-LOGIN " <> controller.credentials["api_key"]}]
end
