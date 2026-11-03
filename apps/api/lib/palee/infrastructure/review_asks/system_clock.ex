defmodule Palee.Infrastructure.ReviewAsks.SystemClock do
  @moduledoc "The real clock of review asks (ADR-355)."

  @behaviour Palee.ReviewAsks.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
