defmodule Palee.ContentTranslations.TranslationStore do
  @moduledoc "Facade over the translations adapter (ADR-520); calls run in the caller's tenant session."

  @behaviour Palee.ContentTranslations.Ports.TranslationStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :content_translation_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def list(context, locale), do: call(context, :list, [locale])
  @impl true
  def list_many(context, locales), do: call(context, :list_many, [locales])
  @impl true
  def put_many(context, locale, rows), do: call(context, :put_many, [locale, rows])
  @impl true
  def delete_many(context, locale, keys), do: call(context, :delete_many, [locale, keys])
end
