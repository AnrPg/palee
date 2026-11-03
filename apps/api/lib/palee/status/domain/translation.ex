defmodule Palee.Status.Domain.Translation do
  @moduledoc """
  ADR-366: incidents are written in any language and the status page also
  shows them in English.

  * The console asks for a machine translation first (`Ports.Translator`),
    shows it as an editable preview marked «αυτόματη μετάφραση», and sends
    what the person kept with the incident: the source `locale`, `title_en`
    and `body_en`, and `en_source` (`auto` when untouched, `edited` when
    corrected).
  * When translation fails, the incident is published without English: the
    page then shows the original text to everyone.
  * Text already in English carries no English copy.

  Pure.
  """

  @sources ~w(auto edited)
  @locale ~r/^[a-z]{2,3}(?:[-_][a-z0-9]{2,8})?$/

  @type fields :: %{
          locale: String.t() | nil,
          title_en: String.t() | nil,
          body_en: String.t() | nil,
          en_source: String.t() | nil
        }

  @doc "The source language as stored: a lowercase language tag, or nil when unknown."
  def locale(value) when is_binary(value) do
    tag = value |> String.trim() |> String.downcase() |> String.replace("_", "-")
    if Regex.match?(@locale, tag) and String.length(tag) <= 8, do: tag
  end

  def locale(_value), do: nil

  @doc "The base language of a tag (`el-gr` → `el`), nil-safe."
  def language(nil), do: nil
  def language(tag) when is_binary(tag), do: tag |> String.split(["-", "_"]) |> hd()

  @doc """
  The translation fields of a new incident (`:incident`, title and note) or
  of a new step (`:update`, note only), from the request. `{:ok, fields}` or
  `{:error, :invalid_status_translation}`.
  """
  def from_params(params, kind) when kind in [:incident, :update] do
    locale = params |> get(:locale) |> locale()
    title_en = params |> get(:title_en) |> trim()
    body_en = params |> get(:body_en) |> trim()

    cond do
      language(locale) == "en" ->
        {:ok, empty(locale)}

      kind == :incident and is_nil(title_en) and is_nil(body_en) ->
        {:ok, empty(locale)}

      kind == :update and is_nil(body_en) ->
        {:ok, empty(locale)}

      kind == :incident and not (valid_title?(title_en) and valid_body?(body_en)) ->
        {:error, :invalid_status_translation}

      kind == :update and not valid_body?(body_en) ->
        {:error, :invalid_status_translation}

      true ->
        {:ok,
         %{
           locale: locale,
           title_en: if(kind == :incident, do: title_en),
           body_en: body_en,
           en_source: source(get(params, :en_source))
         }}
    end
  end

  @doc """
  What the console asks to translate: an optional title (3–140 characters)
  and a note (1–2000). `{:ok, %{title, body}}` or `{:error, reason}`.
  """
  def request(params) do
    title = params |> get(:title) |> trim()
    body = params |> get(:body) |> trim()

    cond do
      not valid_body?(body) -> {:error, :invalid_status_note}
      not (is_nil(title) or valid_title?(title)) -> {:error, :invalid_status_title}
      true -> {:ok, %{title: title, body: body}}
    end
  end

  @doc """
  A translator's answer made safe to show: trimmed, within the stored
  limits, with the detected language. `{:ok, %{locale, title, body}}` or
  `{:error, :status_translation_unavailable}`.
  """
  def result(%{body: body} = answer) when is_binary(body) do
    title = answer |> Map.get(:title) |> trim()
    body = trim(body)
    locale = answer |> Map.get(:locale) |> locale()

    if valid_body?(body) and (is_nil(title) or valid_title?(clip(title, 140))) do
      {:ok, %{locale: locale, title: title && clip(title, 140), body: clip(body, 2000)}}
    else
      {:error, :status_translation_unavailable}
    end
  end

  def result(_answer), do: {:error, :status_translation_unavailable}

  @doc """
  The title and note a reader sees: the original when the reader's language
  is the one it was written in (or there is no English copy), else the
  English copy. `machine` says the English is a machine translation.
  """
  def for_reader(%{} = incident, %{} = update, reader_locale) do
    source = incident.locale || update.locale
    has_english = is_binary(incident.title_en) or is_binary(update.body_en)
    english = has_english and language(locale(reader_locale)) != language(source)

    %{
      title: pick(english, incident.title_en, incident.title),
      body: pick(english, update.body_en, update.body),
      machine: english and (update.en_source || incident.en_source) == "auto"
    }
  end

  defp pick(true, english, _original) when is_binary(english), do: english
  defp pick(_english?, _english, original), do: original

  defp empty(locale), do: %{locale: locale, title_en: nil, body_en: nil, en_source: nil}

  defp source(value) when value in @sources, do: value
  defp source(_value), do: "auto"

  defp valid_title?(value), do: is_binary(value) and String.length(value) in 3..140
  defp valid_body?(value), do: is_binary(value) and String.length(value) in 1..2000

  defp clip(value, max), do: String.slice(value, 0, max)

  defp get(params, key), do: Map.get(params, key, Map.get(params, to_string(key)))

  defp trim(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim(_value), do: nil
end
