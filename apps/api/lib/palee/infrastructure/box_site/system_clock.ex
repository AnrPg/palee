defmodule Palee.Infrastructure.BoxSite.SystemClock do
  @moduledoc "The real clock of the website services (ADR-352)."

  @behaviour Palee.BoxSite.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
