defmodule Palee.Retention.SignalReader do
  @moduledoc "Facade over the risk signals read model (ADR-347); runs in the box's scope."

  @behaviour Palee.Retention.Ports.SignalReader

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :retention_signal_reader)

  @impl true
  def signals(context, today, now),
    do: RepoContext.run(context, fn -> adapter().signals(context, today, now) end)
end
