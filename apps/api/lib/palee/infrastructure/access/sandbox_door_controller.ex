defmodule Palee.Infrastructure.Access.SandboxDoorController do
  @moduledoc """
  The door controller of development, tests and demos (ADR-381): no
  hardware. `settings.simulate` = `offline` answers every opening as an
  unreachable controller (saving still works, as for a controller that went
  offline after it was set up), so the fail-secure path can be tried
  without a real door.
  Events are given as `%{"event" => "door_opened" | "door_forced" | ...}`.
  """

  @behaviour Palee.Access.Ports.DoorController

  @impl true
  def unlock(%{settings: %{"simulate" => "offline"}}, _seconds),
    do: {:error, {:offline, :simulated}}

  def unlock(_controller, seconds) when is_integer(seconds) and seconds > 0, do: :ok

  @impl true
  def check(_controller), do: :ok

  @impl true
  def parse_event(_controller, %{"event" => event}) when is_binary(event) and event != "" do
    {:ok, [%{event: String.slice(event, 0, 80), occurred_at: nil}]}
  end

  def parse_event(_controller, _params), do: {:error, :invalid_event}
end
