defmodule Palee.Application.BoxSite.PublicSite do
  @moduledoc """
  ADR-352..355: what a visitor of a box's website reads and sends, without an
  account. The box resolves only when its public page is published (ADR-142);
  the web composes this with `/api/public/boxes/:slug` and its packages.

  Every read projects public fields only: section keys, FAQ, public tag ids
  (never the Conversions API token), the Google reviews link and, when the
  owner turned it on, a timetable without spots, bookings or people.
  """

  alias Palee.Application.{PublicBox, PublicURL}
  alias Palee.Application.BoxSite.SiteOutbox
  alias Palee.{BoxSite, ReviewAsks}

  @doc "The site of a published box."
  def show(slug) do
    with {:ok, box, context} <- PublicBox.resolve(slug) do
      settings = BoxSite.settings(context)
      place_id = ReviewAsks.settings(context).google_place_id
      faq = settings.faq || []

      facts = %{
        public_schedule: settings.public_schedule,
        faq?: faq != [],
        forms_enabled: settings.forms_enabled,
        reviews?: not is_nil(place_id)
      }

      sections = BoxSite.visible_sections(settings.section_order, settings.hidden_sections, facts)

      {:ok,
       %{
         slug: box.slug,
         canonical_url: canonical_url(box),
         sections: sections,
         faq: if("faq" in sections, do: faq, else: []),
         forms: %{
           trial: "trial_form" in sections,
           contact: "contact_form" in sections,
           kinds: BoxSite.form_kinds()
         },
         reviews: %{google_reviews_url: ReviewAsks.read_reviews_url(place_id)},
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
      Map.merge(attrs, %{conversion_status: "pending", conversion_payload: event, conversion_next_at: now})
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

  defp stringify(params), do: Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
end
