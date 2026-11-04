defmodule Palee.ContentTranslations.Domain.TranslationPolicy do
  @moduledoc """
  ADR-500: the rules of translated content, pure.

    * A translation remembers the hash of the source it was made from. When
      the source changes, the translation is `:stale` (still shown, flagged).
    * Status of one text in one language: `:missing` (none), `:stale`,
      `:machine` (a machine wrote it and nobody checked it yet) or `:ok`.
    * A person's text is always `manual` and checked; a machine's text is
      `machine` and unchecked until someone keeps it.
    * Machine translation only fills what is missing or stale: it never
      replaces a person's up-to-date text.
    * An empty translation deletes the row (the site then shows the source).
  """

  alias Palee.ContentTranslations.Domain.Subjects

  # The app's languages (`Palee.Identity.Domain.Locale.supported/0`); a test
  # keeps the two lists equal.
  @locales ~w(en el ar ru de es pt-PT he it bg nl fr)
  @statuses [:missing, :stale, :machine, :ok]

  @type status :: :missing | :stale | :machine | :ok
  @type key :: {String.t(), String.t(), String.t()}

  @doc "Every language a text can be translated into."
  @spec locales() :: [String.t()]
  def locales, do: @locales

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "`{:ok, locale}` in canonical casing (`pt-pt` → `pt-PT`), or `{:error, :unsupported_locale}`."
  @spec locale(term()) :: {:ok, String.t()} | {:error, :unsupported_locale}
  def locale(value) when is_binary(value) do
    wanted = value |> String.trim() |> String.replace("_", "-") |> String.downcase()

    case Enum.find(@locales, &(String.downcase(&1) == wanted)) do
      nil -> {:error, :unsupported_locale}
      locale -> {:ok, locale}
    end
  end

  def locale(_value), do: {:error, :unsupported_locale}

  @doc "The base language of a locale (`pt-PT` → `pt`), to compare with a source language."
  @spec base(String.t()) :: String.t()
  def base(locale), do: locale |> String.split("-") |> hd() |> String.downcase()

  @doc """
  The languages a business translates into and shows, cleaned: canonical,
  without duplicates or the source language, visible ⊆ translated.
  `{:error, field}` names the list that holds an unknown language.
  """
  @spec languages(term(), term(), String.t()) ::
          {:ok, %{translation_locales: [String.t()], visible_locales: [String.t()]}}
          | {:error, :translation_locales | :visible_locales}
  def languages(translated, visible, source_language) do
    with {:ok, translated} <- locale_list(translated, source_language, :translation_locales),
         {:ok, visible} <- locale_list(visible, source_language, :visible_locales) do
      {:ok,
       %{
         translation_locales: translated,
         visible_locales: Enum.filter(visible, &(&1 in translated))
       }}
    end
  end

  defp locale_list(values, source_language, field) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case locale(value) do
        {:ok, locale} -> {:cont, {:ok, [locale | acc]}}
        {:error, _} -> {:halt, {:error, field}}
      end
    end)
    |> case do
      {:ok, list} ->
        {:ok,
         list
         |> Enum.reverse()
         |> Enum.uniq()
         |> Enum.reject(&(base(&1) == base(source_language)))}

      error ->
        error
    end
  end

  defp locale_list(_values, _source_language, field), do: {:error, field}

  @doc "The fingerprint of a source text (sha256, lowercase hex). `nil` counts as empty."
  @spec source_hash(String.t() | nil) :: String.t()
  def source_hash(text), do: :sha256 |> :crypto.hash(text || "") |> Base.encode16(case: :lower)

  @doc "The status of one source text against its translation row (or nil)."
  @spec status(String.t() | nil, map() | nil) :: status()
  def status(_source, nil), do: :missing

  def status(source, %{source_hash: hash} = row) do
    cond do
      hash != source_hash(source) -> :stale
      row.origin == "machine" and is_nil(row.reviewed_at) -> :machine
      true -> :ok
    end
  end

  @doc "Whether a machine may (re)write this text."
  @spec machine_may_write?(status()) :: boolean()
  def machine_may_write?(status), do: status in [:missing, :stale]

  @doc "How many texts are in each status."
  @spec counts([status()]) :: %{status() => non_neg_integer()}
  def counts(statuses) do
    Map.merge(Map.new(@statuses, &{&1, 0}), Enum.frequencies(statuses))
  end

  @doc """
  One edit from a person: `%{"kind", "id", "field", "text"}`. Answers
  `{:ok, {:put, key, text}}`, `{:ok, {:delete, key}}` for an empty text, or
  `{:error, {:invalid_fields, ...}}`.
  """
  @spec edit(term()) :: {:ok, {:put, key(), String.t()} | {:delete, key()}} | {:error, term()}
  def edit(%{} = params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    kind = params["kind"]
    field = params["field"]

    with true <- Subjects.known?(kind, field) || {:error, invalid(:field)},
         {:ok, id} <- uuid(params["id"]),
         {:ok, text} <- text(params["text"], Subjects.max_length(kind, field)) do
      key = {kind, id, field}
      if text, do: {:ok, {:put, key, text}}, else: {:ok, {:delete, key}}
    end
  end

  def edit(_params), do: {:error, invalid(:entries)}

  @doc "A text a machine answered, cleaned to the field's limit; nil when unusable."
  @spec machine_text({String.t(), String.t(), String.t()}, term()) :: String.t() | nil
  def machine_text({kind, _id, field}, text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      text -> String.slice(text, 0, Subjects.max_length(kind, field))
    end
  end

  def machine_text(_key, _text), do: nil

  @doc "A row for a person's text, made from `source`."
  @spec manual_row(key(), String.t(), String.t() | nil, DateTime.t(), term()) :: map()
  def manual_row({kind, id, field}, text, source, now, user_id) do
    %{
      subject_kind: kind,
      subject_id: id,
      field: field,
      text: text,
      source_hash: source_hash(source),
      origin: "manual",
      reviewed_at: now,
      updated_by_id: user_id
    }
  end

  @doc "A row for a machine's text, made from `source`, unchecked."
  @spec machine_row(key(), String.t(), String.t() | nil) :: map()
  def machine_row({kind, id, field}, text, source) do
    %{
      subject_kind: kind,
      subject_id: id,
      field: field,
      text: text,
      source_hash: source_hash(source),
      origin: "machine",
      reviewed_at: nil,
      updated_by_id: nil
    }
  end

  @doc "The text key as the API writes it: `kind:id:field`."
  @spec key_string(key()) :: String.t()
  def key_string({kind, id, field}), do: Enum.join([kind, id, field], ":")

  @doc "Parses `kind:id:field`."
  @spec parse_key(term()) :: {:ok, key()} | {:error, term()}
  def parse_key(value) when is_binary(value) do
    with [kind, id, field] <- String.split(value, ":"),
         true <- Subjects.known?(kind, field),
         {:ok, id} <- uuid(id) do
      {:ok, {kind, id, field}}
    else
      _invalid -> {:error, invalid(:keys)}
    end
  end

  def parse_key(_value), do: {:error, invalid(:keys)}

  defp uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, invalid(:id)}
    end
  end

  defp uuid(_value), do: {:error, invalid(:id)}

  defp text(nil, _max), do: {:ok, nil}

  defp text(value, max) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> {:ok, nil}
      String.length(value) > max -> {:error, invalid(:text, "too_long")}
      true -> {:ok, value}
    end
  end

  defp text(_value, _max), do: {:error, invalid(:text)}

  defp invalid(field, code \\ "invalid"), do: {:invalid_fields, %{field => code}}
end
