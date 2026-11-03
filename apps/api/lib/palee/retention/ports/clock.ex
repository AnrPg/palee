defmodule Palee.Retention.Ports.Clock do
  @moduledoc """
  The time ADR-347 runs on, injected so tests can stand at any moment
  (`config :palee, :retention_clock`).
  """

  @callback now() :: DateTime.t()
end
