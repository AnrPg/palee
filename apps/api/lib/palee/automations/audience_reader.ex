defmodule Palee.Automations.AudienceReader do
  @moduledoc "Facade over the audience read model (ADR-346); runs in the box's scope."

  @behaviour Palee.Automations.Ports.Audience

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :automation_audience)

  @impl true
  def absent_members(context, today, days),
    do: RepoContext.run(context, fn -> adapter().absent_members(context, today, days) end)

  @impl true
  def ending_subscriptions(context, today, days),
    do: RepoContext.run(context, fn -> adapter().ending_subscriptions(context, today, days) end)
end
