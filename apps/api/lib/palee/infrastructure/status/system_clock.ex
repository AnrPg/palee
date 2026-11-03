defmodule Palee.Infrastructure.Status.SystemClock do
  @moduledoc "The system clock of the status page (ADR-364)."

  @behaviour Palee.Status.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
