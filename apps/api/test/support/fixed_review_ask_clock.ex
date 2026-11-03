defmodule Palee.TestSupport.FixedReviewAskClock do
  @moduledoc "ADR-355 tests: noon UTC today, so the daytime rule holds in Europe/Athens."

  @behaviour Palee.ReviewAsks.Ports.Clock

  @impl true
  def now, do: DateTime.new!(Date.utc_today(), ~T[10:00:00.000000], "Etc/UTC")
end
