defmodule Palee.Leads.Ports.Clock do
  @moduledoc """
  The time ADR-344 runs on, injected so tests can stand at any moment
  (`config :palee, :leads_clock`).
  """

  @callback now() :: DateTime.t()
end
