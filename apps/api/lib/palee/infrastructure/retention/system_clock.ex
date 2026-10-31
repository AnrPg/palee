defmodule Palee.Infrastructure.Retention.SystemClock do
  @moduledoc "The real clock (ADR-347)."

  @behaviour Palee.Retention.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
