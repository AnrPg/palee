defmodule Palee.Infrastructure.Access.ShellyDoorController do
  @moduledoc """
  A Shelly relay on the door strike or turnstile contact, through the Shelly
  Cloud Control API v2 (ADR-381;
  https://shelly-api-docs.shelly.cloud/cloud-control-api/communication-v2).

    * open: `POST https://<server>/v2/devices/api/set/switch?auth_key=…`
      with `{"id", "channel", "on": true, "toggle_after": seconds}`; the
      relay switches itself off after `toggle_after`, on the device, even if
      Palee or the cloud go away in between, so a door is never left open;
    * check: `POST …/v2/devices/api/get` with `{"ids": [id], "select":
      ["status"]}`, which also says whether the device is online;
    * events: a Shelly *action* (Gen2 webhook) on the door contact input
      calls Palee's event URL with `?event=door_opened` (or `door_closed`,
      `door_forced`).

  The cloud allows one call per second per account, plenty for a door.
  """

  @behaviour Palee.Access.Ports.DoorController

  alias Palee.Infrastructure.Access.Http

  @events ~w(door_opened door_closed door_forced door_held_open)

  @impl true
  def unlock(controller, seconds) do
    body = %{
      id: controller.settings["device_id"],
      channel: controller.settings["channel"] || 0,
      on: true,
      toggle_after: seconds
    }

    with {:ok, _response} <- call(controller, "/v2/devices/api/set/switch", body), do: :ok
  end

  @impl true
  def check(controller) do
    body = %{ids: [controller.settings["device_id"]], select: ["status"]}

    case call(controller, "/v2/devices/api/get", body) do
      {:ok, %{body: [%{"online" => false} | _rest]}} -> {:error, {:offline, :device_offline}}
      {:ok, %{body: [_device | _rest]}} -> :ok
      {:ok, _empty} -> {:error, {:rejected, :device_not_found}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def parse_event(_controller, %{"event" => event}) when event in @events,
    do: {:ok, [%{event: event, occurred_at: nil}]}

  def parse_event(_controller, _params), do: {:error, :invalid_event}

  defp call(controller, path, body) do
    Http.request(
      method: :post,
      url: "https://#{controller.settings["server"]}#{path}",
      params: [auth_key: controller.credentials["auth_key"]],
      json: body
    )
  end
end
