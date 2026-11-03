defmodule Palee.Infrastructure.Clock.SystemClock do
  @moduledoc "The system clock behind `Palee.Application.Clock`."

  @behaviour Palee.Application.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
