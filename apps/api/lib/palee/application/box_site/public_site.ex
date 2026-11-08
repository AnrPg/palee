defmodule Palee.Application.BoxSite.PublicSite do
  @moduledoc """
  ADR-352..355: what a visitor of a box's website reads and sends, without an
  account. The box resolves only when its public page is published (ADR-142);
  the web composes this with `/api/public/boxes/:slug` and its packages.

  Every read projects public fields only: section keys, FAQ, public tag ids
  (never the Conversions API token), the Google reviews link and, when the
  owner turned it on, a timetable without spots, bookings or people.

  ADR-388 (v3.1) adds the box's events open to everyone, «WOD της ημέρας»
  (only when the owner turns it on), the in-app reviews next to the Google
  rating (ADR-386/387), and the site's languages: the box's own plus the
  translations the owner shows (ADR-520, before that English only).

  ADR-530 adds the look (`template`, `palette`, `appearance`,
  `calm_motion`), `photos` (the page and room photos; no site video yet:
  tenant uploads take images only), `stats` (aggregates, never a person),
  `programmes` (the programmes for sale, ADR-370) and
  `preview/2`, the same read with the draft applied for the box's staff.
  `phone` stays null: the box has no public phone yet (the fiscal identity's
  phone is private).
  """

  alias Palee.Application.{PublicBox, PublicURL}
  alias Palee.Application.BoxSite.{SiteOutbox, SiteProgrammes, SiteTranslations}
  alias Palee.Application.Payments.PackageAudience
  alias Palee.Application.ReviewAsks.BoxReviews
  alias Palee.{BoxSite, Community, Organizations, Pantheon, ReviewAsks, Scheduling, Workouts}
  alias Palee.Scheduling.DayWorkoutStore
  alias Palee.TimeZones.ZonedTime

  @events_shown 6
  @wods_shown 3
  @photos_shown 12

  @doc """
  The site of a published box. `language` (ADR-520) picks one of the
  site's translations: the box's texts then come translated where the
  owner (or a machine) translated them, the box's own text otherwise;
  `texts` holds the translations of what other reads serve (packages, rooms,
  locations), keyed `kind:id:field`, and `class_type_names` the class names.
  """
  def show(slug, language \\ nil) do
    with {:ok, box, context} <- PublicBox.resolve(slug) do
      {:ok, build(box, context, BoxSite.settings(context), language)}
    end
  end

  @doc """
  ADR-530: the staff member's own site as it will look once the draft is
  published, in the same shape as `show/2`. It works before the box
  published its public page (the box is then found by its organization, and
  the photos come from the public page's last «Δημοσίευση», if any).
  """
  def preview(%{organization_id: organization_id} = context, language \\ nil) do
    case Organizations.get_by_id(organization_id) do
      %{slug: slug} ->
        box = %{organization_id: organization_id, slug: slug}
        {:ok, build(box, context, BoxSite.drafted_settings(context), language)}

      nil ->
        {:error, :not_found}
    end
  end

  defp build(box, context, settings, language) do
    place_id = ReviewAsks.settings(context).google_place_id
    faq = settings.faq || []
    reviews = BoxReviews.public(context, place_id)
    hidden = settings.hidden_sections
    zone = Organizations.organization_timezone(box.organization_id) || "Etc/UTC"
    languages = SiteTranslations.site_languages(context, settings)
    texts = SiteTranslations.published(context, settings, language)
    translated = canonical_language(language, tl(languages))
    tr = fn kind, id, field, original -> Map.get(texts, "#{kind}:#{id}:#{field}", original) end
    week = week_slots(context)
    photos = if "photos" in hidden, do: [], else: photos(context, tr)
    stats = if "stats" in hidden, do: nil, else: stats(box, week, zone)
    programmes = SiteProgrammes.list(context, box.slug)

    facts = %{
      public_schedule: settings.public_schedule,
      public_wod: Map.get(settings, :public_wod, false),
      faq?: faq != [],
      forms_enabled: settings.forms_enabled,
      reviews?: not is_nil(place_id) or reviews.palee.count > 0,
      photos?: photos != [],
      stats?: stats_shown?(stats),
      programmes?: programmes != [],
      # ADR-553: the website's «Πακέτα» follows who sees the packages.
      packages?: PackageAudience.view(context, nil).packages != []
    }

    sections = BoxSite.visible_sections(settings.section_order, hidden, facts)

    %{
      slug: box.slug,
      canonical_url: canonical_url(box),
      sections: sections,
      template: settings.template,
      palette: settings.palette,
      appearance: settings.appearance,
      calm_motion: settings.calm_motion,
      language: hd(languages),
      languages: languages,
      translation: translated,
      time_zone: zone,
      phone: nil,
      about:
        if("about" in sections,
          do: Map.get(texts, "box_profile:#{box.organization_id}:about"),
          else: nil
        ),
      texts: texts,
      class_type_names: class_type_names(texts, context),
      photos: %{items: if("photos" in sections, do: photos, else: []), video: nil},
      stats: if("stats" in sections, do: stats, else: nil),
      programmes: if("programmes" in sections, do: programmes, else: []),
      programmes_total: if("programmes" in sections, do: SiteProgrammes.total(context), else: 0),
      events:
        if("events" in sections,
          do:
            Enum.map(
              events(context, box),
              &%{&1 | title: tr.("event", &1.id, "title", &1.title)}
            ),
          else: []
        ),
      wod: if("wod" in sections, do: wods(context, zone), else: []),
      faq:
        if("faq" in sections,
          do: Enum.map(faq, &translated_faq(&1, tr)),
          else: []
        ),
      forms: %{
        trial: "trial_form" in sections,
        contact: "contact_form" in sections,
        kinds: BoxSite.form_kinds()
      },
      reviews:
        if("reviews" in sections,
          do: Map.put(reviews, :google_reviews_url, ReviewAsks.read_reviews_url(place_id)),
          else: %{google_reviews_url: nil, palee: nil, google: nil}
        ),
      tracking: %{
        tags: BoxSite.public_tags(settings),
        consent_required: BoxSite.tracking?(settings),
        banner_version: settings.banner_version,
        categories: BoxSite.consent_categories(),
        validity_days: BoxSite.consent_validity_days()
      },
      timetable:
        if("schedule" in sections,
          do: Enum.map(timetable(week), &translated_slot(&1, tr)),
          else: []
        ),
      # ADR-397: where anyone reports content on the site (DSA Art. 16).
      report_contact: ReviewAsks.moderation_contact()
    }
  end

  # ADR-530 «Φωτογραφίες»: the public page's cover and photos, then the room
  # photos marked public (captioned with the photo's caption or the room's
  # name), at most @photos_shown.
  defp photos(context, tr) do
    page =
      context
      |> PublicBox.profile_photos()
      |> Enum.map(&Map.put(Map.take(&1, [:id, :url, :width, :height]), :caption, nil))

    rooms =
      context
      |> PublicBox.rooms()
      |> Enum.flat_map(fn room ->
        name = tr.("space", room.id, "name", room.name)

        Enum.map(room.photos, fn photo ->
          %{
            id: photo.id,
            url: photo.url,
            width: photo.width,
            height: photo.height,
            caption: blank_to(Map.get(photo, :caption), name)
          }
        end)
      end)

    (page ++ rooms)
    |> Enum.reject(&is_nil(&1.url))
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(@photos_shown)
  rescue
    _error -> []
  end

  defp blank_to(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  defp blank_to(_value, fallback), do: fallback

  # ADR-530 «Αριθμοί κοινότητας»: aggregates only. Classes over the next 7
  # days, PRs recorded in the box this calendar year (the gym's zone) and
  # whole years since the box joined (nil before the first).
  defp stats(box, week, zone) do
    today = ZonedTime.local_date(BoxSite.clock().now(), zone)

    %{
      classes_per_week: length(week),
      prs_this_year: prs_this_year(box.organization_id, today),
      years_open: years_open(box.organization_id, today)
    }
  end

  defp prs_this_year(organization_id, today) do
    Pantheon.count_organization_records(organization_id, Date.new!(today.year, 1, 1), today)
  rescue
    _error -> nil
  end

  defp years_open(organization_id, today) do
    case Organizations.get_by_id(organization_id) do
      %{inserted_at: %DateTime{} = created} -> whole_years(DateTime.to_date(created), today)
      _missing -> nil
    end
  end

  defp whole_years(from, today) do
    years = today.year - from.year
    years = if {today.month, today.day} < {from.month, from.day}, do: years - 1, else: years
    if years >= 1, do: years, else: nil
  end

  defp stats_shown?(nil), do: false

  defp stats_shown?(stats),
    do: stats |> Map.values() |> Enum.any?(&(is_integer(&1) and &1 > 0))

  # ADR-388: the box's next events that anyone may join (no goers shown).
  defp events(context, box) do
    now = BoxSite.clock().now()

    context
    |> Community.list_events(%{
      organization_ids: [box.organization_id],
      open_only: true,
      from: now,
      limit: @events_shown
    })
    |> Enum.map(fn event ->
      %{
        id: event.id,
        title: event.title,
        starts_at: event.starts_at,
        ends_at: event.ends_at,
        time_zone: event.time_zone,
        place_name: event.place_name,
        price_cents: event.price_cents,
        currency: event.currency
      }
    end)
  rescue
    _error -> []
  end

  # ADR-388: today's WOD (the gym's day), as staff set it for the day.
  defp wods(context, zone) do
    today = ZonedTime.local_date(BoxSite.clock().now(), zone)

    context
    |> DayWorkoutStore.list_rules(today, today)
    |> Enum.map(& &1.master_workout_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(@wods_shown)
    |> Enum.map(&Workouts.get_workout(context, &1))
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn workout ->
      %{
        id: workout.id,
        date: today,
        title: workout.title,
        type: workout |> Map.get(:type) |> then(&(&1 && to_string(&1))),
        body: Map.get(workout, :body)
      }
    end)
  rescue
    _error -> []
  end

  # The next 7 days' classes (the public box page's default window).
  defp week_slots(context) do
    start_at = DateTime.utc_now() |> DateTime.truncate(:second)

    Scheduling.get_calendar_week(context, %{
      start_at: start_at,
      end_at: DateTime.add(start_at, 7 * 86_400, :second),
      class_type_ids: []
    })
  rescue
    _error -> []
  end

  # ADR-352 §3: the week's classes, without spots, bookings or people.
  defp timetable(slots) do
    Enum.map(slots, fn slot ->
      class_type = Map.get(slot, :class_type)

      %{
        id: slot.id,
        name: (class_type && class_type.name) || slot.name,
        class_type_id: class_type && class_type.id,
        scheduled_at: slot.scheduled_at,
        duration_minutes: slot.duration_minutes,
        location_id: Map.get(slot, :location_id)
      }
    end)
  end

  # ADR-520: the FAQ and timetable in the visitor's language.
  defp translated_faq(entry, tr) do
    id = entry["id"]

    %{
      "id" => id,
      "question" => tr.("site_faq", id, "question", entry["question"]),
      "answer" => tr.("site_faq", id, "answer", entry["answer"])
    }
  end

  defp translated_slot(%{class_type_id: nil} = slot, _tr), do: slot

  defp translated_slot(%{class_type_id: id} = slot, tr),
    do: %{slot | name: tr.("class_type", id, "name", slot.name)}

  defp class_type_names(texts, _context) when texts == %{}, do: %{}

  defp class_type_names(texts, context) do
    context
    |> Scheduling.list_class_types()
    |> Enum.flat_map(fn class_type ->
      case Map.get(texts, "class_type:#{class_type.id}:name") do
        nil -> []
        name -> [{class_type.name, name}]
      end
    end)
    |> Map.new()
  end

  defp canonical_language(language, languages),
    do: Enum.find(languages, &(String.downcase(&1) == String.downcase(language || "")))

  defp canonical_url(box) do
    case BoxSite.primary_host(box.organization_id) do
      nil -> PublicURL.base_url() <> "/b/" <> box.slug
      host -> "https://" <> host
    end
  end

  @doc "The box behind a custom host, for the web's host rewrite."
  def by_host(host) when is_binary(host) do
    case BoxSite.site_by_host(String.downcase(host)) do
      %{status: status} = site ->
        if BoxSite.serving?(status) do
          {:ok,
           %{
             slug: site.slug,
             host: site.host,
             primary: site.primary,
             primary_host: BoxSite.primary_host(site.organization_id)
           }}
        else
          {:error, :not_found}
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Caddy's on-demand TLS `ask`: `:ok` only for verified hosts."
  def tls_allowed(host) when is_binary(host) do
    case BoxSite.site_by_host(String.downcase(host)) do
      %{status: status} -> if BoxSite.tls_allowed?(status), do: :ok, else: {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def tls_allowed(_host), do: {:error, :not_found}

  @doc """
  A trial or contact form: `{:ok, :received}` (also for a dropped bot post),
  `{:error, :site_forms_closed}` or field errors.
  """
  def submit_form(slug, kind, params) do
    params = stringify(params)

    with {:ok, box, context} <- PublicBox.resolve(slug),
         settings = BoxSite.settings(context),
         :ok <- forms_open(settings),
         false <- BoxSite.spam?(params),
         now = BoxSite.clock().now(),
         {:ok, attrs} <- BoxSite.validate_submission(kind, params, now) do
      attrs =
        attrs
        |> Map.put(:id, Ecto.UUID.generate())
        |> with_conversion(context, settings, box, now, event_id(params))

      {:ok, _submission} = BoxSite.insert_submission(context, attrs)
      SiteOutbox.schedule(context)
      {:ok, :received}
    else
      true -> {:ok, :received}
      error -> error
    end
  end

  defp forms_open(%{forms_enabled: true}), do: :ok
  defp forms_open(_settings), do: {:error, :site_forms_closed}

  # ADR-354 §5: only with the visitor's unexpired marketing consent.
  defp with_conversion(attrs, context, settings, box, now, event_id) do
    granted =
      settings.conversions_api_enabled and is_binary(attrs.visitor_id) and
        BoxSite.effective_consent(context, attrs.visitor_id, settings.banner_version, now).marketing

    event =
      granted &&
        BoxSite.conversion_event(
          %{Map.take(attrs, [:id, :email, :phone, :submitted_at]) | id: event_id || attrs.id},
          canonical_url(box)
        )

    if event do
      Map.merge(attrs, %{
        conversion_status: "pending",
        conversion_payload: event,
        conversion_next_at: now
      })
    else
      attrs
    end
  end

  # The browser Pixel sends the same eventID, so Meta deduplicates the Lead.
  defp event_id(%{"event_id" => value}) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp event_id(_params), do: nil

  @doc "Records a visitor's consent choice; answers what it allows."
  def record_consent(slug, params) do
    params = stringify(params)

    with {:ok, _box, context} <- PublicBox.resolve(slug) do
      settings = BoxSite.settings(context)
      now = BoxSite.clock().now()

      with {:ok, consent} <- BoxSite.record_consent(context, params, settings.banner_version, now) do
        choice = %{analytics: consent.analytics, marketing: consent.marketing}

        {:ok,
         %{
           analytics: consent.analytics,
           marketing: consent.marketing,
           banner_version: consent.banner_version,
           expires_at: consent.expires_at,
           allowed_tags: BoxSite.allowed_tags(BoxSite.public_tags(settings), choice)
         }}
      end
    end
  end

  defp stringify(params),
    do: Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
end
