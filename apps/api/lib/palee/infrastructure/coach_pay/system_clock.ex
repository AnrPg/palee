defmodule Palee.Infrastructure.CoachPay.SystemClock do
  @moduledoc "The real clock for coach pay (ADR-341)."

  @behaviour Palee.CoachPay.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
