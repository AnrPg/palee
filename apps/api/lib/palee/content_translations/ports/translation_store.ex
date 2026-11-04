defmodule Palee.ContentTranslations.Ports.TranslationStore do
  @moduledoc """
  ADR-520: persistence of translated texts. Every callback takes the tenant
  context first and runs under its row-level security.

  A row: `%{subject_kind, subject_id, field, locale, text, source_hash,
  origin, reviewed_at, updated_by_id, updated_at}`. `put_many/3` writes rows
  of one language in one statement (insert or replace per text).
  """

  @type context :: map()
  @type key :: {kind :: String.t(), id :: Ecto.UUID.t(), field :: String.t()}

  @callback list(context(), locale :: String.t()) :: [map()]
  @callback list_many(context(), locales :: [String.t()]) :: [map()]
  @callback put_many(context(), locale :: String.t(), rows :: [map()]) ::
              {:ok, [map()]} | {:error, term()}
  @callback delete_many(context(), locale :: String.t(), [key()]) :: non_neg_integer()
end
