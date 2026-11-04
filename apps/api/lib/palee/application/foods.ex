defmodule Palee.Application.Foods do
  @moduledoc """
  «Σάρωση barcode» in meals and «Δικά μου τρόφιμα» (ADR-376, CP-D9).

  A scan looks first at the person's own foods, then at Palee's cache of
  public products, and asks the chain of free sources only on a miss
  (ADR-421: Open Food Facts, USDA FoodData Central, licensed product lists;
  once, inside a total budget; a slow or failed call is left to the outbox
  worker and the answer is `pending`). A product nobody knows, or a shop's
  own code, ends in the manual entry, which saves a custom food with that
  barcode, optionally prefilled from a photo of its label. Every scan that
  found nothing is counted per barcode and country (no person) so the team
  sees the gaps. Other members' own foods are never used: they are theirs.

  Own foods stay private unless the person ticks «Μοιράσου το» for a product
  with a barcode (ADR-421 addendum): then the product alone (barcode, name,
  brand, portion, nutrition per 100 g; nothing about them) goes into the
  public cache as `palee_members`, unless a public source or an earlier
  share already has it, and is queued for Open Food Facts. Who shared is kept
  for abuse handling only.

  What the person sees follows `NutrientDisclosure`: never energy, macros
  only with a coach's plan that sets them and `hide_macros` off. The
  feature is optional and only offered where meals are (vision §4.10).
  Who scanned what is never stored.
  """

  alias Palee.Application.Clock
  alias Palee.{Nutrition, Places, Wellness}
  alias Palee.Nutrition.{FoodContributor, FoodDatabase, FoodLabelReader, FoodStore}
  alias Palee.Nutrition.Domain.FoodSharePolicy
  alias Palee.Organizations.PlatformContext

  @default_language "el"
  @label_content_types ~w(image/jpeg image/png image/webp)
  @max_label_bytes 4 * 1_024 * 1_024
  @misses_limit 200
  @shares_per_run 10

  def barcode(%{user_id: user_id} = context, raw, language \\ @default_language) do
    case Nutrition.parse_barcode(raw) do
      {:error, reason} ->
        {:error, reason}

      {:in_store, code} ->
        {:ok,
         result(code, "manual", nil, nil, false)
         |> Map.merge(%{reason: "in_store_code", label_reading: FoodLabelReader.available?()})}

      {:ok, code} ->
        visible? = macros_visible?(context, user_id)

        case FoodStore.with_context(context, fn ->
               FoodStore.custom_food_by_barcode(user_id, code)
             end) do
          %{} = food ->
            {:ok, result(code, "found", "custom", present_custom(food, visible?), visible?)}

          nil ->
            code |> from_cache(language, visible?) |> after_scan(context)
        end
    end
  end

  # ADR-421: a scan that ended in the manual entry because no source has the
  # product is counted; the label photo is offered when it can run.
  defp after_scan(%{status: "manual", reason: reason} = result, context) do
    if reason == "not_found",
      do: :ok = FoodStore.record_miss(result.barcode, country(context), Clock.today())

    {:ok, Map.put(result, :label_reading, FoodLabelReader.available?())}
  end

  defp after_scan(result, _context), do: {:ok, result}

  defp country(context) do
    case Places.home_country(context) do
      code when is_binary(code) ->
        code = String.upcase(code)
        if Regex.match?(~r/^[A-Z]{2}$/, code), do: code, else: ""

      _none ->
        ""
    end
  end

  defp from_cache(code, language, visible?) do
    now = Clock.now()
    row = FoodStore.get_cached(code)

    case Nutrition.food_cache_decision(row, now) do
      :serve ->
        present_cached(row, visible?)

      {:serve, :refresh} ->
        :ok = FoodStore.request_lookup(code, now)
        present_cached(row, visible?)

      :wait ->
        code |> lookup_now(language, now) |> present_cached(visible?)

      :lookup ->
        :ok = FoodStore.request_lookup(code, now)
        code |> lookup_now(language, now) |> present_cached(visible?)
    end
  end

  # One inline attempt when this request can claim the row; another request
  # already asking means `pending`.
  defp lookup_now(code, language, now) do
    case FoodStore.claim(code, now, 1) do
      [row] -> run_lookup(row, language, now)
      [] -> FoodStore.get_cached(code)
    end
  end

  @doc "The outbox worker: looks up due barcodes. Returns how many were handled."
  def process_due(limit \\ 20) do
    now = Clock.now()
    rows = FoodStore.claim(:due, now, limit)
    Enum.each(rows, &run_lookup(&1, @default_language, now))
    {:ok, length(rows)}
  end

  defp run_lookup(row, language, now) do
    outcome =
      case FoodDatabase.lookup(row.barcode, language) do
        {:ok, attrs} ->
          {:ok,
           Map.put(
             attrs,
             :portion_hint,
             Nutrition.portion_hint(attrs.nutrients, attrs.categories)
           )}

        other ->
          other
      end

    # The row as it is now: a member may have shared the product meanwhile.
    current = FoodStore.get_cached(row.barcode) || row

    {:ok, saved} =
      FoodStore.finish(row.barcode, Nutrition.food_after_lookup(outcome, current, now), now)

    saved
  end

  defp present_cached(%{status: "found"} = row, visible?) do
    food = %{
      id: nil,
      name: row.name,
      brand: row.brand,
      quantity: row.quantity,
      serving_size: row.serving_size,
      image_url: row.image_url,
      portion_hint: row.portion_hint,
      nutrients: Nutrition.visible_nutrients(row.nutrients, visible?)
    }

    row.barcode
    |> result("found", row.source, food, visible?)
    |> Map.put(:attribution, Nutrition.food_attribution(row.source, row.barcode, row.attribution))
  end

  defp present_cached(%{status: status} = row, visible?) when status in ~w(not_found failed),
    do: result(row.barcode, "manual", nil, nil, visible?) |> Map.put(:reason, status)

  defp present_cached(%{barcode: code}, visible?), do: result(code, "pending", nil, nil, visible?)

  defp result(code, status, source, food, visible?) do
    %{
      barcode: code,
      status: status,
      source: source,
      food: food,
      macros_visible: visible?,
      attribution: nil,
      reason: nil,
      label_reading: false
    }
  end

  # «Φωτογραφία ετικέτας» (ADR-421) ------------------------------------------

  @doc """
  Reads a label from one or two photos (front, nutrition table) into the
  prefill of «Δικό μου τρόφιμο». The photos are only read in this request,
  never stored; nothing is saved until the person saves the form. Numbers
  follow `NutrientDisclosure` like every other food.
  """
  def read_label(%{user_id: user_id} = context, photos, locale) do
    with :ok <- label_reading_available(),
         {:ok, images} <- label_images(photos),
         {:ok, reading} <-
           FoodLabelReader.read(images, %{locale: locale}, label_metering(context)),
         {:ok, prefill} <- Nutrition.food_label_prefill(reading) do
      visible? = macros_visible?(context, user_id)

      {:ok,
       %{
         food: %{
           name: prefill.name,
           brand: prefill.brand,
           serving_label: prefill.serving_label,
           portion_hint:
             if(prefill.nutrients == %{},
               do: nil,
               else: Nutrition.portion_hint(prefill.nutrients, [])
             ),
           nutrients: Nutrition.visible_nutrients(prefill.nutrients, visible?)
         },
         macros_visible: visible?
       }}
    else
      {:error, :not_configured} ->
        {:error, :label_reading_unavailable}

      {:error, reason} when reason in [:label_reading_unavailable, :invalid_label_photo] ->
        {:error, reason}

      {:error, :label_unreadable} ->
        {:error, :label_unreadable}

      {:error, _reason} ->
        {:error, :label_unreadable}
    end
  end

  defp label_reading_available,
    do: if(FoodLabelReader.available?(), do: :ok, else: {:error, :label_reading_unavailable})

  defp label_images(photos) do
    images = photos |> List.wrap() |> Enum.reject(&is_nil/1)

    if images != [] and length(images) <= 2 and Enum.all?(images, &label_image?/1),
      do: {:ok, images},
      else: {:error, :invalid_label_photo}
  end

  defp label_image?(%{bytes: bytes, content_type: type}) when is_binary(bytes),
    do: type in @label_content_types and byte_size(bytes) in 1..@max_label_bytes

  defp label_image?(_image), do: false

  # ADR-152: metered for the person; no gym is involved in their own meals.
  defp label_metering(context) do
    %{
      organization_id: nil,
      user_id: Map.get(context, :user_id),
      operation_id: Ecto.UUID.generate(),
      feature: "food_label"
    }
  end

  # Barcodes nobody had (platform console, ADR-421) --------------------------

  def barcode_misses(%PlatformContext{}, params) do
    country =
      case params |> params_map() |> Map.get("country") do
        code when is_binary(code) and code != "" -> String.upcase(code)
        _all -> nil
      end

    misses =
      country
      |> FoodStore.list_misses(@misses_limit)
      |> Enum.map(&Map.take(&1, [:barcode, :country, :scans, :first_seen_on, :last_seen_on]))

    {:ok, %{misses: misses}}
  end

  def barcode_misses(_context, _params), do: {:error, :vendor_required}

  # Custom foods ------------------------------------------------------------

  def list(%{user_id: user_id} = context) do
    visible? = macros_visible?(context, user_id)

    foods =
      FoodStore.with_context(context, fn -> FoodStore.list_custom_foods(user_id) end)
      |> Enum.map(&present_custom(&1, visible?))

    {:ok, %{foods: foods, macros_visible: visible?}}
  end

  def create(%{user_id: user_id} = context, params) do
    with {:ok, attrs} <- custom_attrs(params),
         {:ok, share?} <- share_choice(params, attrs[:barcode]),
         {:ok, food} <-
           FoodStore.with_context(context, fn ->
             FoodStore.insert_custom_food(Map.put(attrs, :user_id, user_id))
           end) do
      {:ok,
       food |> maybe_share(share?, context) |> present_custom(macros_visible?(context, user_id))}
    end
  end

  def update(%{user_id: user_id} = context, id, params) do
    with {:ok, attrs} <- custom_attrs(params),
         %{} = food <-
           FoodStore.with_context(context, fn -> FoodStore.get_custom_food(id, user_id) end) ||
             {:error, :not_found},
         {:ok, share?} <- share_choice(params, Map.get(attrs, :barcode, food.barcode)),
         {:ok, food} <-
           FoodStore.with_context(context, fn -> FoodStore.update_custom_food(food, attrs) end) do
      {:ok,
       food |> maybe_share(share?, context) |> present_custom(macros_visible?(context, user_id))}
    end
  end

  # «Μοιράσου το» (ADR-421 addendum): only when asked, only for a product
  # barcode (a shop's own code belongs to no product).
  defp share_choice(params, barcode) do
    case params |> params_map() |> Map.get("share") do
      share when share in [true, "true"] ->
        in_store? = match?({:in_store, _code}, barcode && Nutrition.parse_barcode(barcode))

        if FoodSharePolicy.shareable_barcode?(barcode, in_store?),
          do: {:ok, true},
          else: {:error, :share_needs_barcode}

      _not_asked ->
        {:ok, false}
    end
  end

  defp maybe_share(food, false, _context), do: food
  defp maybe_share(%{shared_at: %DateTime{}} = food, true, _context), do: food

  defp maybe_share(food, true, %{user_id: user_id} = context) do
    now = Clock.now()
    language = context |> Map.get(:account) |> locale() |> FoodSharePolicy.language()
    share = FoodSharePolicy.share_attrs(food, user_id, language, now)

    case FoodStore.share_product(share, FoodSharePolicy.cache_attrs(share, now)) do
      :shared ->
        {:ok, food} =
          FoodStore.with_context(context, fn ->
            FoodStore.update_custom_food(food, %{shared_at: now})
          end)

        food

      :exists ->
        food
    end
  end

  defp locale(%{preferred_locale: locale}), do: locale
  defp locale(_account), do: nil

  @doc """
  The Open Food Facts outbox (ADR-421 addendum): sends due shares when a
  Palee account for Open Food Facts is configured; without one they wait.
  Returns how many were handled.
  """
  def process_shares(limit \\ @shares_per_run) do
    if FoodContributor.configured?() do
      now = Clock.now()
      shares = FoodStore.claim_shares(now, limit)

      Enum.each(shares, fn share ->
        outcome = FoodContributor.contribute(share)

        :ok =
          FoodStore.finish_share(
            share.barcode,
            FoodSharePolicy.after_contribution(outcome, share, now),
            now
          )
      end)

      {:ok, length(shares)}
    else
      {:ok, 0}
    end
  end

  def delete(%{user_id: user_id} = context, id) do
    FoodStore.with_context(context, fn ->
      case FoodStore.get_custom_food(id, user_id) do
        nil -> {:error, :not_found}
        food -> FoodStore.delete_custom_food(food)
      end
    end)
  end

  defp custom_attrs(params) do
    given = params_map(params)

    with {:ok, code} <- custom_barcode(given["barcode"]),
         {:ok, nutrients} <- Nutrition.cast_food_nutrients(given["nutrients"]) do
      attrs =
        for key <- ~w(name brand serving_label note portion_hint barcode nutrients),
            Map.has_key?(given, key),
            into: %{} do
          case key do
            "barcode" -> {:barcode, code}
            "nutrients" -> {:nutrients, nutrients}
            other -> {String.to_existing_atom(other), given[other]}
          end
        end

      if Map.has_key?(given, "nutrients") and not Map.has_key?(given, "portion_hint"),
        do: {:ok, Map.put(attrs, :portion_hint, Nutrition.portion_hint(nutrients, []))},
        else: {:ok, attrs}
    end
  end

  defp custom_barcode(nil), do: {:ok, nil}

  defp custom_barcode(raw) do
    case Nutrition.parse_barcode(raw) do
      {:ok, code} -> {:ok, code}
      {:in_store, code} -> {:ok, code}
      error -> error
    end
  end

  # The person's own food shows its own numbers only where macros may show.
  defp present_custom(food, visible?) do
    %{
      id: food.id,
      barcode: food.barcode,
      name: food.name,
      brand: food.brand,
      quantity: nil,
      serving_size: food.serving_label,
      image_url: nil,
      portion_hint: food.portion_hint,
      note: food.note,
      shared_at: food.shared_at,
      nutrients: Nutrition.visible_nutrients(food.nutrients, visible?)
    }
  end

  defp macros_visible?(context, user_id) do
    plans = Nutrition.list_own_plans(context)
    prefs = Wellness.with_context(context, fn -> Wellness.preferences(user_id) end)
    Nutrition.macros_visible?(plans, prefs.hide_macros == true)
  end

  defp params_map(params) when is_struct(params), do: params |> Map.from_struct() |> params_map()

  defp params_map(params) when is_map(params),
    do: Map.new(params, fn {k, v} -> {to_string(k), v} end)

  defp params_map(_params), do: %{}
end
