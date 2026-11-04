defmodule Palee.Application.BoxSite.SiteTranslations do
  @moduledoc """
  ADR-500: «Μεταφράσεις» of the box's website. Composes the texts the box
  wrote that its website shows, from the contexts that own them, and hands
  them to `Palee.ContentTranslations` as sources:

    * «Σχετικά» (the published about text) and the rooms with public photos;
    * the FAQ;
    * the packages sold online (name, description);
    * the class types (timetable and coaches);
    * the upcoming events open to everyone;
    * the locations.

  Only texts of sections the website shows are listed, so the owner never
  translates what nobody sees. The box's own language is the source; any
  other language of the app can be a translation.
  """

  alias Palee.Application.Payments.OnlineSales
  alias Palee.Application.PublicBox
  alias Palee.Application.ReviewAsks.BoxReviews
  alias Palee.{BoxSite, Community, ContentTranslations, Facility, Organizations, Scheduling}

  @events_listed 50

  # The groups in the order the website shows them.
  @groups ~w(about rooms faq packages classes events locations)

  @doc "The groups of texts, in the website's order."
  def groups, do: @groups

  # ── Staff ───────────────────────────────────────────────────────────────

  @doc """
  The texts of the website with their translation in `locale`, the counts
  per status, and whether machine translation can run.
  """
  def show(context, locale) do
    with {:ok, locale} <- target_locale(context, locale) do
      sources = sources(context)
      %{items: items, counts: counts} = ContentTranslations.overview(context, locale, sources)
      meta = Map.new(sources, &{&1.key, &1})

      {:ok,
       %{
         locale: locale,
         source_language: source_language(context),
         machine_available: ContentTranslations.machine_available?(),
         counts: counts,
         total: length(items),
         items: Enum.map(items, &present_item(&1, Map.fetch!(meta, &1.key)))
       }}
    end
  end

  @doc "Counts per status for each language the box translates into."
  def progress(context, settings \\ nil) do
    settings = settings || BoxSite.settings(context)
    source = source_language(context)
    sources = sources(context, settings)

    locales =
      Enum.reject(
        settings.translation_locales,
        &(ContentTranslations.base_language(&1) == source)
      )

    ContentTranslations.progress(context, locales, sources)
    |> Map.new(fn {locale, counts} ->
      {locale, %{counts: counts, total: length(sources)}}
    end)
  end

  @doc "A person's edits (`entries`) in `locale`; answers the page again."
  def save(context, locale, entries) do
    with {:ok, locale} <- target_locale(context, locale),
         {:ok, _keys} <-
           ContentTranslations.save(
             context,
             locale,
             entries,
             sources(context),
             user_id(context),
             BoxSite.clock().now()
           ) do
      show(context, locale)
    end
  end

  @doc "«Εντάξει, κράτα το» for `keys` (`kind:id:field`); answers the page again."
  def keep(context, locale, keys) when is_list(keys) do
    with {:ok, locale} <- target_locale(context, locale),
         {:ok, keys} <- parse_keys(keys),
         {:ok, _count} <-
           ContentTranslations.keep(
             context,
             locale,
             keys,
             sources(context),
             user_id(context),
             BoxSite.clock().now()
           ) do
      show(context, locale)
    end
  end

  def keep(_context, _locale, _keys), do: {:error, {:invalid_fields, %{keys: "invalid"}}}

  @doc """
  «Αυτόματη μετάφραση»: a machine fills every missing or out-of-date text of
  `locale`; answers the page again with how many it wrote.
  """
  def machine_translate(context, locale) do
    with {:ok, locale} <- target_locale(context, locale),
         {:ok, written} <-
           ContentTranslations.machine_translate(
             context,
             locale,
             source_language(context),
             sources(context),
             %{
               business_name: business_name(context),
               metering: %{
                 feature: "site_translation",
                 organization_id: context.organization_id,
                 user_id: user_id(context)
               }
             }
           ),
         {:ok, page} <- show(context, locale) do
      {:ok, Map.put(page, :written, written)}
    end
  end

  @doc """
  The website's language settings from an edit: canonical, the box's own
  language left out, visible ⊆ translated. Leaves `params` alone when it
  holds neither list.
  """
  def clean_languages(context, params) do
    translated = Map.get(params, "translation_locales")
    visible = Map.get(params, "visible_locales")

    if is_nil(translated) and is_nil(visible) do
      {:ok, params}
    else
      current = BoxSite.settings(context)

      case ContentTranslations.languages(
             translated || current.translation_locales,
             visible || current.visible_locales,
             source_language(context)
           ) do
        {:ok, %{translation_locales: translated, visible_locales: visible}} ->
          {:ok,
           Map.merge(params, %{"translation_locales" => translated, "visible_locales" => visible})}

        {:error, field} ->
          {:error, {:invalid_fields, %{field => "invalid"}}}
      end
    end
  end

  # ── Visitors ────────────────────────────────────────────────────────────

  @doc """
  The languages a visitor can pick: the box's own first, then the visible
  translations (only ones of the app's languages, never the box's own).
  """
  def site_languages(context, settings) do
    source = source_language(context)

    visible =
      settings
      |> Map.get(:visible_locales, [])
      |> Enum.reject(&(ContentTranslations.base_language(&1) == source))

    [source | visible]
  end

  @doc """
  What a visitor reads in `locale` (when the box shows it): `%{"kind:id:field"
  => text}`, or `%{}` for the box's own language or a hidden one.
  """
  def published(context, settings, locale) do
    with {:ok, locale} <- ContentTranslations.locale(locale || ""),
         true <- locale in site_languages(context, settings),
         false <- ContentTranslations.base_language(locale) == source_language(context) do
      ContentTranslations.published(context, locale, sources(context, settings))
    else
      _other -> %{}
    end
  end

  # ── Sources ─────────────────────────────────────────────────────────────

  @doc """
  Every text the website shows: `%{key: {kind, id, field}, text, group,
  label}`; `label` names what a text belongs to (the package of a
  description, the room of a description) when the text alone does not.
  """
  def sources(context, settings \\ nil) do
    settings = settings || BoxSite.settings(context)
    sections = shown_sections(settings)

    [
      if("about" in sections, do: about(context), else: []),
      if("about" in sections, do: rooms(context), else: []),
      if("faq" in sections, do: faq(settings), else: []),
      if("packages" in sections, do: packages(context), else: []),
      if("schedule" in sections or "coaches" in sections, do: class_types(context), else: []),
      if("events" in sections, do: events(context), else: []),
      if("location" in sections, do: locations(context), else: [])
    ]
    |> List.flatten()
    |> Enum.filter(&present?(&1.text))
  end

  defp shown_sections(settings) do
    faq = settings.faq || []

    BoxSite.visible_sections(settings.section_order, settings.hidden_sections, %{
      public_schedule: settings.public_schedule,
      public_wod: Map.get(settings, :public_wod, false),
      faq?: faq != [],
      forms_enabled: settings.forms_enabled,
      reviews?: false
    })
  end

  defp about(%{organization_id: organization_id} = context) do
    profile = Organizations.get_public_profile(context)
    snapshot = (profile && profile.published_snapshot) || %{}
    [source("about", {"box_profile", organization_id, "about"}, snapshot["about"])]
  end

  defp rooms(context) do
    context
    |> PublicBox.rooms()
    |> Enum.flat_map(fn room ->
      [
        source("rooms", {"space", room.id, "name"}, room.name),
        source("rooms", {"space", room.id, "description"}, room.description, room.name)
      ]
    end)
  rescue
    _error -> []
  end

  defp faq(settings) do
    (settings.faq || [])
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {entry, number} ->
      case entry["id"] do
        id when is_binary(id) ->
          [
            source("faq", {"site_faq", id, "question"}, entry["question"], number),
            source("faq", {"site_faq", id, "answer"}, entry["answer"], number)
          ]

        _no_id ->
          []
      end
    end)
  end

  defp packages(context) do
    context
    |> OnlineSales.listed_packages()
    |> Enum.flat_map(fn package ->
      [
        source("packages", {"package", package.id, "name"}, package[:name]),
        source(
          "packages",
          {"package", package.id, "description"},
          package[:description],
          package[:name]
        )
      ]
    end)
  rescue
    _error -> []
  end

  defp class_types(context) do
    context
    |> Scheduling.list_class_types()
    |> Enum.reject(&Map.get(&1, :archived_at))
    |> Enum.map(&source("classes", {"class_type", &1.id, "name"}, &1.name))
  end

  defp events(context) do
    context
    |> Community.list_events(%{
      organization_ids: [context.organization_id],
      open_only: true,
      from: BoxSite.clock().now(),
      limit: @events_listed
    })
    |> Enum.map(&source("events", {"event", &1.id, "title"}, &1.title))
  rescue
    _error -> []
  end

  defp locations(context) do
    context
    |> Facility.list_locations()
    |> Enum.filter(&is_nil(Map.get(&1, :archived_at)))
    |> Enum.map(&source("locations", {"location", &1.id, "name"}, &1.name))
  end

  defp source(group, key, text, label \\ nil),
    do: %{key: key, text: text, group: group, label: label && to_string(label)}

  defp present?(text), do: is_binary(text) and String.trim(text) != ""

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp present_item(item, meta) do
    {kind, id, field} = item.key

    %{
      key: ContentTranslations.key_string(item.key),
      kind: kind,
      id: id,
      field: field,
      group: meta.group,
      label: meta.label,
      source: item.source,
      text: item.text,
      status: item.status,
      origin: item.origin,
      updated_at: item.updated_at
    }
  end

  # A language the box may translate into: one of the app's, not its own.
  defp target_locale(context, value) do
    with {:ok, locale} <- ContentTranslations.locale(value || "") do
      if ContentTranslations.base_language(locale) == source_language(context),
        do: {:error, {:invalid_fields, %{locale: "source_language"}}},
        else: {:ok, locale}
    else
      {:error, _reason} -> {:error, {:invalid_fields, %{locale: "invalid"}}}
    end
  end

  defp parse_keys(keys) do
    Enum.reduce_while(keys, {:ok, []}, fn value, {:ok, acc} ->
      case ContentTranslations.parse_key(value) do
        {:ok, key} -> {:cont, {:ok, [key | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  @doc "The box's own language (the source of every translation)."
  def source_language(context), do: BoxReviews.box_language(context.organization_id)

  defp business_name(%{organization_id: organization_id}) do
    settings = Organizations.get_organization_settings(organization_id)
    organization = Organizations.get_by_id(organization_id)
    (settings && settings.brand_name) || (organization && organization.name)
  end

  defp user_id(context), do: Map.get(context, :user_id)
end
