defmodule Palee.Infrastructure.Status.SandboxProbe do
  @moduledoc """
  ADR-364: the probe for dev and test. Every component is operational
  unless `config :palee, :status_sandbox_results` (a map of component key
  to `{status, reason}`) says otherwise.
  """

  @behaviour Palee.Status.Ports.DependencyProbe

  alias Palee.Status.Domain.Components

  @impl true
  def check do
    overrides = Application.get_env(:palee, :status_sandbox_results, %{})

    Enum.map(Components.all(), fn key ->
      {status, reason} = Map.get(overrides, key, {"operational", nil})
      %{component: key, status: status, reason: reason}
    end)
  end
end
