defmodule Palee.Ranks.SignatureStore do
  @moduledoc """
  Dispatches the diploma signature port to the configured adapter (ADR-377
  addendum). `scope` is the person (`%{user_id: id}`) or `:system` (no
  acting person: drawing a diploma, account deletion).
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  @type scope :: %{required(:user_id) => Ecto.UUID.t(), optional(atom()) => term()} | :system

  @doc "Runs `fun` in the scope's session."
  def run(:system, fun) when is_function(fun, 0), do: fun.()

  def run(%{user_id: user_id}, fun) when is_binary(user_id) and is_function(fun, 0),
    do: RepoContext.run(%{user_id: user_id}, fun)

  def run(_scope, _fun), do: {:error, :missing_ownership_scope}

  def current(scope, user_id), do: run(scope, fn -> adapter().current(user_id) end)
  def get(scope, id), do: run(scope, fn -> adapter().get(id) end)
  def list(scope, user_id), do: run(scope, fn -> adapter().list(user_id) end)

  def replace(scope, user_id, attrs, now),
    do: run(scope, fn -> adapter().replace(user_id, attrs, now) end)

  def remove(scope, user_id, now), do: run(scope, fn -> adapter().remove(user_id, now) end)
  def events(scope, user_id), do: run(scope, fn -> adapter().events(user_id) end)

  defp adapter, do: Application.fetch_env!(:palee, :diploma_signature_store)
end
