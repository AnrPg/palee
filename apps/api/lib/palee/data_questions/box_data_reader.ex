defmodule Palee.DataQuestions.BoxDataReader do
  @moduledoc false
  @behaviour Palee.DataQuestions.Ports.BoxDataReader

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :box_data_reader)

  @impl true
  def run(context, query, params, zone) do
    RepoContext.run(context, fn -> adapter().run(context, query, params, zone) end)
  end
end
