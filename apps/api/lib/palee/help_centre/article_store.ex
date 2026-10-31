defmodule Palee.HelpCentre.ArticleStore do
  @moduledoc false
  @behaviour Palee.HelpCentre.Ports.ArticleStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :help_article_store)

  # The Palee team's writes and draft reads run in their own session so the
  # row policies see the acting vendor; anonymous reads need no session.
  defp call(%{user_id: user_id} = context, function, args) when is_binary(user_id) do
    RepoContext.run(%{user_id: user_id}, fn -> apply(adapter(), function, [context | args]) end)
  end

  defp call(context, function, args), do: apply(adapter(), function, [context | args])

  @impl true
  def list_published(locales), do: adapter().list_published(locales)
  @impl true
  def list_all(context, filters), do: call(context, :list_all, [filters])
  @impl true
  def get(context, slug, locale), do: call(context, :get, [slug, locale])
  @impl true
  def upsert(context, slug, locale, attrs), do: call(context, :upsert, [slug, locale, attrs])
  @impl true
  def delete(context, slug, locale), do: call(context, :delete, [slug, locale])
  @impl true
  def seed(context, rows), do: call(context, :seed, [rows])
end
