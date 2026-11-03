defmodule Palee.Application.Clock do
  @moduledoc "Dispatches the application clock port to the configured adapter (ADR-043 §5)."

  @behaviour Palee.Application.Ports.Clock

  @impl true
  def now, do: Application.fetch_env!(:palee, :application_clock).now()

  @doc "Today in UTC by the configured clock."
  def today, do: now() |> DateTime.to_date()
end
