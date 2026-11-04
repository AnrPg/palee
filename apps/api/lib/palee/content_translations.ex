defmodule Palee.ContentTranslations do
  @moduledoc """
  The ContentTranslations bounded context (ADR-500): translations of the
  texts a business writes (its «Σχετικά», FAQ, packages, class types,
  events, rooms, locations) into the app's other languages.

  The context never reads the texts themselves: callers pass the current
  sources as `%{key: {kind, id, field}, text: source}` (composed in
  `Palee.Application.*` from the contexts that own them), and the context
  keeps one translation per text and language, with the hash of the source
  it was made from.

  Machine translation (`Ports.MachineTranslator`) only fills what is
  missing or out of date and never replaces a person's current text.
  """

  alias Palee.ContentTranslations.Domain.{Subjects, TenantDataPolicy, TranslationPolicy}
  alias Palee.ContentTranslations.TranslationStore

  @machine_batch 40
  @machine_batch_chars 12_000

  @type key :: TranslationPolicy.key()
  @type source :: %{key: key(), text: String.t()}

  # ── Ports and vocabularies ──────────────────────────────────────────────

  @doc "The configured machine translator (`ContentTranslations.Ports.MachineTranslator`)."
  def machine_translator, do: Application.fetch_env!(:palee, :content_machine_translator)

  @doc "Whether machine translation can run now."
  def machine_available?, do: machine_translator().available?()

  defdelegate locales(), to: TranslationPolicy
  defdelegate locale(value), to: TranslationPolicy
  defdelegate base_language(locale), to: TranslationPolicy, as: :base
  defdelegate languages(translated, visible, source_language), to: TranslationPolicy
  defdelegate statuses(), to: TranslationPolicy
  defdelegate key_string(key), to: TranslationPolicy
  defdelegate parse_key(value), to: TranslationPolicy
  defdelegate subject_kinds(), to: Subjects, as: :kinds
  defdelegate subject_fields(kind), to: Subjects, as: :fields

  # ── Reads ───────────────────────────────────────────────────────────────

  @doc """
  Every source with its translation in `locale` and status:
  `%{key, source, text, status, origin, updated_at}` in the sources' order,
  plus the counts per status.
  """
  @spec overview(map(), String.t(), [source()]) :: %{items: [map()], counts: map()}
  def overview(context, locale, sources) do
    rows = rows_by_key(TranslationStore.list(context, locale))
    items = Enum.map(sources, &item(&1, Map.get(rows, &1.key)))
    %{items: items, counts: TranslationPolicy.counts(Enum.map(items, & &1.status))}
  end

  @doc "Counts per status for each of `locales` (one read)."
  @spec progress(map(), [String.t()], [source()]) :: %{String.t() => map()}
  def progress(_context, [], _sources), do: %{}

  def progress(context, locales, sources) do
    by_locale = context |> TranslationStore.list_many(locales) |> Enum.group_by(& &1.locale)

    Map.new(locales, fn locale ->
      rows = rows_by_key(Map.get(by_locale, locale, []))

      counts =
        sources
        |> Enum.map(&TranslationPolicy.status(&1.text, Map.get(rows, &1.key)))
        |> TranslationPolicy.counts()

      {locale, counts}
    end)
  end

  @doc """
  What a visitor reads in `locale`: `%{"kind:id:field" => text}` for every
  source that has a translation (out-of-date ones too: better than none).
  """
  @spec published(map(), String.t(), [source()]) :: %{String.t() => String.t()}
  def published(context, locale, sources) do
    rows = rows_by_key(TranslationStore.list(context, locale))

    for %{key: key} <- sources, %{text: text} <- [Map.get(rows, key)], into: %{} do
      {TranslationPolicy.key_string(key), text}
    end
  end

  defp item(%{key: key, text: source}, row) do
    %{
      key: key,
      source: source,
      text: row && row.text,
      status: TranslationPolicy.status(source, row),
      origin: row && row.origin,
      updated_at: row && row.updated_at
    }
  end

  defp rows_by_key(rows),
    do: Map.new(rows, &{{&1.subject_kind, &1.subject_id, &1.field}, &1})

  # ── Writes ──────────────────────────────────────────────────────────────

  @doc """
  A person's edits in `locale` (`[%{"kind","id","field","text"}]`): each
  text is checked and saved against its current source; an empty text
  removes the translation. A text that is not among `sources` (deleted,
  hidden) is refused with `{:error, :unknown_translation_text}`.
  """
  @spec save(map(), String.t(), [map()], [source()], term(), DateTime.t()) ::
          {:ok, [key()]} | {:error, term()}
  def save(context, locale, edits, sources, user_id, now) when is_list(edits) do
    by_key = Map.new(sources, &{&1.key, &1.text})

    with {:ok, edits} <- collect(edits, &TranslationPolicy.edit/1),
         :ok <- known(Enum.map(edits, &edit_key/1), by_key) do
      {puts, deletes} = Enum.split_with(edits, &match?({:put, _, _}, &1))

      rows =
        Enum.map(puts, fn {:put, key, text} ->
          TranslationPolicy.manual_row(key, text, Map.fetch!(by_key, key), now, user_id)
        end)

      with {:ok, _rows} <- put(context, locale, rows) do
        delete_keys = Enum.map(deletes, &edit_key/1)
        if delete_keys != [], do: TranslationStore.delete_many(context, locale, delete_keys)
        {:ok, Enum.map(edits, &edit_key/1)}
      end
    end
  end

  def save(_context, _locale, _edits, _sources, _user_id, _now),
    do: {:error, {:invalid_fields, %{entries: "invalid"}}}

  @doc """
  «Εντάξει, κράτα το»: a person keeps the translations of `keys` as they
  are, for the current source (machine text becomes checked; an
  out-of-date text becomes current).
  """
  @spec keep(map(), String.t(), [key()], [source()], term(), DateTime.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def keep(context, locale, keys, sources, user_id, now) do
    by_key = Map.new(sources, &{&1.key, &1.text})

    with :ok <- known(keys, by_key) do
      rows = rows_by_key(TranslationStore.list(context, locale))

      kept =
        for key <- Enum.uniq(keys), %{} = row <- [Map.get(rows, key)] do
          key
          |> TranslationPolicy.manual_row(row.text, Map.fetch!(by_key, key), now, user_id)
          |> Map.put(:origin, row.origin)
        end

      with {:ok, written} <- put(context, locale, kept), do: {:ok, length(written)}
    end
  end

  @doc """
  Machine-translates every text of `sources` that is missing or out of
  date in `locale`, from `source_language`. Answers how many it wrote, or
  `{:error, :machine_translation_unavailable}` when the translator is not
  set up or failed before writing anything.
  """
  @spec machine_translate(map(), String.t(), String.t(), [source()], map()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def machine_translate(context, locale, source_language, sources, opts \\ %{}) do
    translator = machine_translator()

    if translator.available?() do
      %{items: items} = overview(context, locale, sources)

      due =
        items
        |> Enum.filter(&(TranslationPolicy.machine_may_write?(&1.status) and present?(&1.source)))

      due
      |> batches()
      |> Enum.reduce_while({:ok, 0}, fn batch, {:ok, written} ->
        case translate_batch(context, translator, locale, source_language, batch, opts) do
          {:ok, count} -> {:cont, {:ok, written + count}}
          {:error, _reason} when written > 0 -> {:halt, {:ok, written}}
          {:error, _reason} -> {:halt, {:error, :machine_translation_unavailable}}
        end
      end)
    else
      {:error, :machine_translation_unavailable}
    end
  end

  defp translate_batch(context, translator, locale, source_language, batch, opts) do
    ids = batch |> Enum.with_index() |> Map.new(fn {item, index} -> {"t#{index}", item} end)

    request = %{
      from: source_language,
      to: locale,
      business_name: Map.get(opts, :business_name),
      texts:
        Enum.map(ids, fn {id, %{key: {kind, _id, field}, source: source}} ->
          %{id: id, kind: "#{kind}.#{field}", text: source}
        end)
        |> Enum.sort_by(& &1.id)
    }

    with {:ok, answers} <- translator.translate(request, Map.get(opts, :metering, %{})) do
      rows =
        for {id, %{key: key, source: source}} <- ids,
            text = TranslationPolicy.machine_text(key, Map.get(answers, id)),
            not is_nil(text) do
          TranslationPolicy.machine_row(key, text, source)
        end

      with {:ok, written} <- put(context, locale, rows), do: {:ok, length(written)}
    end
  end

  defp batches(items) do
    items
    |> Enum.chunk_while(
      {[], 0},
      fn item, {batch, chars} ->
        size = String.length(item.source)

        if batch != [] and
             (length(batch) >= @machine_batch or chars + size > @machine_batch_chars),
           do: {:cont, Enum.reverse(batch), {[item], size}},
           else: {:cont, {[item | batch], chars + size}}
      end,
      fn
        {[], _chars} -> {:cont, {[], 0}}
        {batch, _chars} -> {:cont, Enum.reverse(batch), {[], 0}}
      end
    )
  end

  defp put(_context, _locale, []), do: {:ok, []}
  defp put(context, locale, rows), do: TranslationStore.put_many(context, locale, rows)

  defp present?(text), do: is_binary(text) and String.trim(text) != ""

  defp edit_key({:put, key, _text}), do: key
  defp edit_key({:delete, key}), do: key

  defp known(keys, by_key) do
    if Enum.all?(keys, &Map.has_key?(by_key, &1)),
      do: :ok,
      else: {:error, :unknown_translation_text}
  end

  defp collect(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
