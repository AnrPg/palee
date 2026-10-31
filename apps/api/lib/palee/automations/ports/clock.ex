defmodule Palee.Automations.Ports.Clock do
  @moduledoc """
  The time ADR-346 runs on, injected so tests can stand at any moment
  (`config :palee, :automations_clock`).
  """

  @callback now() :: DateTime.t()
end
