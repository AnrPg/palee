defmodule Palee.Infrastructure.Leads.SystemClock do
  @moduledoc "The real clock (ADR-344)."

  @behaviour Palee.Leads.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
