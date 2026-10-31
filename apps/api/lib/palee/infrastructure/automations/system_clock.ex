defmodule Palee.Infrastructure.Automations.SystemClock do
  @moduledoc "The real clock (ADR-346)."

  @behaviour Palee.Automations.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
