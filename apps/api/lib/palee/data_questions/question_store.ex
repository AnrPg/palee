defmodule Palee.DataQuestions.QuestionStore do
  @moduledoc false
  @behaviour Palee.DataQuestions.Ports.QuestionStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :data_question_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def insert(context, attrs), do: tenant_call(context, :insert, [attrs])
  @impl true
  def get(context, id), do: tenant_call(context, :get, [id])
  @impl true
  def list(context, filters), do: tenant_call(context, :list, [filters])
  @impl true
  def count_since(context, user_id, since), do: tenant_call(context, :count_since, [user_id, since])
end
