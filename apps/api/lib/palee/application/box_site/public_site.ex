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
  rating (ADR-386/387), and the site's languages: the box's own plus
  English, with the optional English texts.
  """

  alias Palee.Application.{PublicBox, PublicURL}
  alias Palee.Application.BoxSite.SiteOutbox
  alias Palee.Application.ReviewAsks.BoxReviews
  alias Palee.{BoxSite, Community, Organizations, ReviewAsks, Workouts}
  alias Palee.Scheduling.DayWorkoutStore
  alias Palee.TimeZones.ZonedTime

  @events_shown 6
  @wods_shown 3

  @doc "The site of a published box."
  def show(slug) do
    with {:ok, box, context} <- PublicBox.resolve(slug) do
      settings = BoxSite.settings(context)
      place_id = ReviewAsks.settings(context).google_place_id
      faq = settings.faq || []
      reviews = BoxReviews.public(context, place_id)

      facts = %{
        public_schedule: settings.public_schedule,
        public_wod: Map.get(settings, :public_wod, false),
        faq?: faq != [],
        forms_enabled: settings.forms_enabled,
        reviews?: not is_nil(place_id) or reviews.palee.count > 0
      }

      sections = BoxSite.visible_sections(settings.section_order, settings.hidden_sections, facts)
      zone = Organizations.organization_timezone(box.organization_id) || "Etc/UTC"
      language = BoxReviews.box_language(box.organization_id)

      {:ok,
       %{
         slug: box.slug,
         canonical_url: canonical_url(box),
         sections: sections,
         language: language,
         languages: Enum.uniq([language, "en"]),
         time_zone: zone,
         about_en: if("about" in sections, do: Map.get(settings, :about_en), else: nil),
         events: if("events" in sections, do: events(context, box), else: []),
         wod: if("wod" in sections, do: wods(context, zone), else: []),
         faq: if("faq" in sections, do: faq, else: []),
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
         timetable: if("schedule" in sections, do: timetable(slug), else: [])
       }}
    end
  end

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

  # ADR-352 §3: the week's classes, without spots, bookings or people.
  defp timetable(slug) do
    case PublicBox.schedule(slug, nil, %{}) do
      {:ok, %{slots: slots}} ->
        Enum.map(slots, fn slot ->
          %{
            id: slot.id,
            name: (slot.class_type && slot.class_type.name) || slot.name,
            class_type_id: slot.class_type && slot.class_type.id,
            scheduled_at: slot.scheduled_at,
            duration_minutes: slot.duration_minutes,
            location_id: slot.location_id
          }
        end)

      _error ->
        []
    end
  end

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
        |> with_conversion(context, settings, box, now)

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
  defp with_conversion(attrs, context, settings, box, now) do
    granted =
      settings.conversions_api_enabled and is_binary(attrs.visitor_id) and
        BoxSite.effective_consent(context, attrs.visitor_id, settings.banner_version, now).marketing

    event =
      granted &&
        BoxSite.conversion_event(
          Map.take(attrs, [:id, :email, :phone, :submitted_at]),
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
