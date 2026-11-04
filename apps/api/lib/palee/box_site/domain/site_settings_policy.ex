defmodule Palee.BoxSite.Domain.SiteSettingsPolicy do
  @moduledoc """
  ADR-352/354: what an owner may set on the website, and which of it is
  public. The Conversions API token is write-only: never in a projection.

  ADR-530: the look (`template`, `palette`, `appearance`, `calm_motion`)
  and the section switches (`hidden_sections`, `public_schedule`,
  `public_wod`) are publishable: an edit of them lands in `draft` (only the
  values that differ from what is live; a draft equal to the live site is
  nil) and goes live with `publish/2`. Every other field saves at once.
  Only keys are validated; colours are presentation and live in the web.
  """

  alias Palee.BoxSite.Domain.SiteSections

  @max_faq 12
  @max_question 200
  @max_answer 1_000
  @max_locales 11
  @locale_format ~r/^[a-z]{2}(-[A-Z]{2})?$/
  @tag_formats %{
    meta_pixel_id: ~r/^[0-9]{5,20}$/,
    ga4_measurement_id: ~r/^G-[A-Z0-9]{4,16}$/,
    gtm_container_id: ~r/^GTM-[A-Z0-9]{4,12}$/
  }

  @templates ~w(arena tiles stories atelier)
  @palettes ~w(palee electric flame sun amber emerald aegean violet fuchsia olive navy mono)
  @appearances ~w(auto light dark)
  @publishable ~w(template palette appearance calm_motion hidden_sections public_schedule public_wod)a

  def max_faq, do: @max_faq
  def templates, do: @templates
  def palettes, do: @palettes
  def appearances, do: @appearances
  @doc "The fields that go live only with «Δημοσίευση» (ADR-530 §2)."
  def publishable_fields, do: @publishable
  def tag_fields, do: Map.keys(@tag_formats) |> Enum.sort()

  @doc "Default settings of a box that never saved any."
  def defaults do
    %{
      section_order: SiteSections.keys(),
      hidden_sections: [],
      # ADR-530: for new boxes the timetable is on and the WOD off.
      public_schedule: true,
      public_wod: false,
      faq: [],
      translation_locales: ["en"],
      visible_locales: ["en"],
      forms_enabled: true,
      meta_pixel_id: nil,
      ga4_measurement_id: nil,
      gtm_container_id: nil,
      banner_version: 1,
      conversions_api_enabled: false,
      has_conversions_api_token: false,
      template: "tiles",
      palette: "palee",
      appearance: "auto",
      calm_motion: false,
      draft: nil,
      published_at: nil,
      template_notice: false,
      lock_version: 0
    }
  end

  @doc """
  Turns an edit (string keys) into changes against `current` (the saved
  settings or `defaults/0`). Returns `{:ok, changes}` or
  `{:error, {:invalid_fields, %{field => code}}}`. A new tag bumps the
  banner version so visitors are asked again (ADR-354 §3). The publishable
  fields come back merged into `:draft` (ADR-530), never as columns.
  """
  def changes(current, params) when is_map(params) do
    {changes, errors} =
      {%{}, %{}}
      |> sections(drafted(current), params)
      |> boolean(params, "public_schedule", :public_schedule)
      |> boolean(params, "public_wod", :public_wod)
      |> one_of(params, "template", :template, @templates)
      |> one_of(params, "palette", :palette, @palettes)
      |> one_of(params, "appearance", :appearance, @appearances)
      |> boolean(params, "calm_motion", :calm_motion)
      |> languages(params)
      |> boolean(params, "forms_enabled", :forms_enabled)
      |> boolean(params, "conversions_api_enabled", :conversions_api_enabled)
      |> faq(params)
      |> tags(params)
      |> token(params)

    errors = conversions_api_errors(current, changes, errors)

    if errors == %{} do
      {:ok, current |> bump_banner(changes) |> into_draft(current)}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  defp sections({changes, errors}, current, params) do
    if Map.has_key?(params, "section_order") or Map.has_key?(params, "hidden_sections") do
      order = Map.get(params, "section_order", current.section_order)
      hidden = Map.get(params, "hidden_sections", current.hidden_sections)

      case SiteSections.validate(order, hidden) do
        {:ok, %{order: order, hidden: hidden}} ->
          {Map.merge(changes, %{section_order: order, hidden_sections: hidden}), errors}

        {:error, field} ->
          {changes, Map.put(errors, field, "invalid")}
      end
    else
      {changes, errors}
    end
  end

  defp boolean({changes, errors}, params, key, field) do
    case Map.fetch(params, key) do
      {:ok, value} when is_boolean(value) -> {Map.put(changes, field, value), errors}
      {:ok, _other} -> {changes, Map.put(errors, field, "invalid")}
      :error -> {changes, errors}
    end
  end

  defp one_of({changes, errors}, params, key, field, allowed) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) ->
        if value in allowed,
          do: {Map.put(changes, field, value), errors},
          else: {changes, Map.put(errors, field, "invalid")}

      {:ok, _other} ->
        {changes, Map.put(errors, field, "invalid")}

      :error ->
        {changes, errors}
    end
  end

  # ── Draft and publish (ADR-530 §2) ──────────────────────────────────────

  # The publishable changes move into the draft, merged with what already
  # waits there; only values that differ from the live site stay.
  defp into_draft(changes, current) do
    {publishable, immediate} = Map.split(changes, @publishable)

    if publishable == %{} do
      immediate
    else
      waiting = current |> draft_values() |> Map.merge(publishable)

      draft =
        waiting
        |> Enum.reject(fn {field, value} -> same?(value, Map.get(current, field)) end)
        |> Map.new(fn {field, value} -> {Atom.to_string(field), value} end)

      Map.put(immediate, :draft, if(draft == %{}, do: nil, else: draft))
    end
  end

  defp same?(a, b) when is_list(a) and is_list(b), do: Enum.sort(a) == Enum.sort(b)
  defp same?(a, b), do: a == b

  @doc """
  The draft's values (atom keys), dropping any key or value that is no
  longer valid; `%{}` when nothing waits.
  """
  def draft_values(%{draft: draft}) when is_map(draft) do
    Enum.reduce(@publishable, %{}, fn field, acc ->
      case Map.fetch(draft, Atom.to_string(field)) do
        {:ok, value} -> if valid_value?(field, value), do: Map.put(acc, field, value), else: acc
        :error -> acc
      end
    end)
  end

  def draft_values(_settings), do: %{}

  defp valid_value?(:template, value), do: value in @templates
  defp valid_value?(:palette, value), do: value in @palettes
  defp valid_value?(:appearance, value), do: value in @appearances

  defp valid_value?(:hidden_sections, value),
    do: match?({:ok, _}, SiteSections.validate([], value))

  defp valid_value?(_boolean, value), do: is_boolean(value)

  @doc "The settings as they will be once the draft is published (the preview)."
  def drafted(settings), do: Map.merge(settings, draft_values(settings))

  @doc """
  «Δημοσίευση»: the changes that put the draft live, clear it, stamp
  `published_at` and hide the notice of a moved site.
  """
  def publish(settings, now) do
    settings
    |> draft_values()
    |> Map.merge(%{draft: nil, published_at: now, template_notice: false})
  end

  defp faq({changes, errors}, %{"faq" => entries}) when is_list(entries) do
    cleaned = Enum.map(entries, &faq_entry/1)

    cond do
      length(entries) > @max_faq -> {changes, Map.put(errors, :faq, "too_many")}
      Enum.any?(cleaned, &is_nil/1) -> {changes, Map.put(errors, :faq, "invalid")}
      true -> {Map.put(changes, :faq, cleaned), errors}
    end
  end

  defp faq({changes, errors}, %{"faq" => _other}), do: {changes, Map.put(errors, :faq, "invalid")}
  defp faq(acc, _params), do: acc

  defp faq_entry(entry) when is_map(entry) do
    entry = Map.new(entry, fn {key, value} -> {to_string(key), value} end)

    with {:ok, question} <- text(entry["question"], @max_question, :required),
         {:ok, answer} <- text(entry["answer"], @max_answer, :required),
         {:ok, id} <- faq_id(entry["id"]) do
      # ADR-520: a stable id per entry (given by `BoxSite` when new), so its
      # translations follow it when the owner reorders the list.
      Map.merge(
        %{"question" => question, "answer" => answer},
        if(id, do: %{"id" => id}, else: %{})
      )
    else
      _invalid -> nil
    end
  end

  defp faq_entry(_entry), do: nil

  defp faq_id(nil), do: {:ok, nil}

  defp faq_id(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> :error
    end
  end

  defp faq_id(_value), do: :error

  defp text(value, max, _need) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> :error
      String.length(value) > max -> :error
      true -> {:ok, value}
    end
  end

  defp text(_value, _max, _need), do: :error

  # ADR-520: the languages the owner translates into and the ones visitors
  # can pick. `Application.BoxSite.SiteAdmin` cleans them against the app's
  # languages and the box's own first; here only their shape is checked.
  defp languages({changes, errors}, params) do
    translated = Map.get(params, "translation_locales", :keep)
    visible = Map.get(params, "visible_locales", :keep)

    case {translated, visible} do
      {:keep, :keep} ->
        {changes, errors}

      {translated, visible} when is_list(translated) and is_list(visible) ->
        cond do
          not locales?(translated) ->
            {changes, Map.put(errors, :translation_locales, "invalid")}

          not locales?(visible) or Enum.any?(visible, &(&1 not in translated)) ->
            {changes, Map.put(errors, :visible_locales, "invalid")}

          true ->
            {Map.merge(changes, %{translation_locales: translated, visible_locales: visible}),
             errors}
        end

      _partial ->
        {changes, Map.put(errors, :translation_locales, "invalid")}
    end
  end

  defp locales?(list),
    do:
      length(list) <= @max_locales and
        Enum.all?(list, &(is_binary(&1) and Regex.match?(@locale_format, &1)))

  defp tags(acc, params) do
    Enum.reduce(@tag_formats, acc, fn {field, format}, {changes, errors} ->
      case Map.fetch(params, Atom.to_string(field)) do
        :error ->
          {changes, errors}

        {:ok, value} when value in [nil, ""] ->
          {Map.put(changes, field, nil), errors}

        {:ok, value} when is_binary(value) ->
          value = value |> String.trim() |> String.upcase()

          if Regex.match?(format, value),
            do: {Map.put(changes, field, value), errors},
            else: {changes, Map.put(errors, field, "invalid")}

        {:ok, _other} ->
          {changes, Map.put(errors, field, "invalid")}
      end
    end)
  end

  defp token({changes, errors}, params) do
    case Map.fetch(params, "conversions_api_token") do
      :error ->
        {changes, errors}

      {:ok, value} when value in [nil, ""] ->
        {Map.put(changes, :conversions_api_token, nil), errors}

      {:ok, value} when is_binary(value) ->
        value = String.trim(value)

        if String.length(value) in 20..512 and not String.contains?(value, [" ", "\n"]),
          do: {Map.put(changes, :conversions_api_token, value), errors},
          else: {changes, Map.put(errors, :conversions_api_token, "invalid")}

      {:ok, _other} ->
        {changes, Map.put(errors, :conversions_api_token, "invalid")}
    end
  end

  # The Conversions API needs the pixel it reports to and a token.
  defp conversions_api_errors(current, changes, errors) do
    enabled = Map.get(changes, :conversions_api_enabled, current.conversions_api_enabled)
    pixel = Map.get(changes, :meta_pixel_id, current.meta_pixel_id)

    has_token =
      case Map.fetch(changes, :conversions_api_token) do
        {:ok, value} -> not is_nil(value)
        :error -> current.has_conversions_api_token
      end

    cond do
      not enabled -> errors
      is_nil(pixel) -> Map.put(errors, :meta_pixel_id, "required")
      not has_token -> Map.put(errors, :conversions_api_token, "required")
      true -> errors
    end
  end

  defp bump_banner(current, changes) do
    added? =
      Enum.any?(Map.keys(@tag_formats), fn field ->
        new = Map.get(changes, field, Map.get(current, field))
        not is_nil(new) and new != Map.get(current, field)
      end)

    if added?, do: Map.put(changes, :banner_version, current.banner_version + 1), else: changes
  end

  @doc "The box's tags as the public site needs them (ids only)."
  def public_tags(settings) do
    Map.new(Map.keys(@tag_formats), &{&1, Map.get(settings, &1)})
  end

  @doc "Whether the site has any tag, so a consent banner is needed at all."
  def tracking?(settings), do: Enum.any?(Map.keys(@tag_formats), &(Map.get(settings, &1) != nil))
end
