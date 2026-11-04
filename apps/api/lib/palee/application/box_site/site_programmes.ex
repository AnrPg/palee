defmodule Palee.Application.BoxSite.SiteProgrammes do
  @moduledoc """
  ADR-530 §3 «Προγράμματα»: the programmes the box sells (ADR-370, published
  and on sale), as its website shows them: `%{id, title, summary, weeks,
  price_cents, currency, cover_url, url}` each, linking to the programme's
  public page on Palee (also from the box's own domain). The section hides while the list is empty.
  ADR-543 adds the cover (ADR-541), sessions per week, level, the rating and
  `total/1` for «Όλα τα προγράμματα (N)».
  """

  alias Palee.Application.Programmes.Storefront
  alias Palee.Application.PublicURL

  @shown 6

  @doc "The box's programmes for sale, newest first, public fields only, at most #{@shown}."
  @spec list(map(), String.t()) :: [map()]
  def list(context, slug) do
    context
    |> Storefront.on_sale(@shown)
    |> Enum.map(fn card ->
      reviews = Map.get(card, :reviews) || %{}

      %{
        id: card.id,
        title: card.title,
        summary: Map.get(card, :summary),
        weeks: Map.get(card, :weeks),
        sessions_per_week: Map.get(card, :sessions_per_week),
        level: Map.get(card, :level),
        price_cents: Map.get(card, :price_cents),
        currency: Map.get(card, :currency),
        cover_url: Map.get(card, :cover_url),
        rating_average: Map.get(reviews, :average),
        rating_count: Map.get(reviews, :count, 0),
        url: PublicURL.base_url() <> "/b/#{slug}/programmes/#{card.id}"
      }
    end)
  rescue
    _error -> []
  end

  @doc "How many programmes the box sells, for «Όλα τα προγράμματα (N)» (ADR-543)."
  @spec total(map()) :: non_neg_integer()
  def total(context) do
    Storefront.on_sale_count(context)
  rescue
    _error -> 0
  end
end
