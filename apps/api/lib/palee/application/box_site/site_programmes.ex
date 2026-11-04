defmodule Palee.Application.BoxSite.SiteProgrammes do
  @moduledoc """
  ADR-530 §3 «Προγράμματα»: the programmes the box sells (ADR-370, published
  and on sale), as its website shows them: `%{id, title, summary, weeks,
  price_cents, currency, cover_url, url}` each, linking to the programme's
  public page on Palee (also from the box's own domain). The section hides while the list is empty. Programmes have no
  cover yet, so `cover_url` is nil and the website draws its own.
  """

  alias Palee.Application.PublicURL
  alias Palee.Programmes

  @shown 6

  @doc "The box's programmes for sale, public fields only, at most #{@shown}."
  @spec list(map(), String.t()) :: [map()]
  def list(context, slug) do
    context
    |> Programmes.list_programmes(%{statuses: ["published"]})
    |> Enum.filter(&Programmes.on_sale?/1)
    |> Enum.take(@shown)
    |> Enum.map(fn programme ->
      version =
        programme.current_version_id &&
          Programmes.get_version(context, programme.current_version_id)

      %{
        id: programme.id,
        title: programme.title,
        summary: Map.get(programme, :summary),
        weeks: version && version.weeks,
        price_cents: Map.get(programme, :price_cents),
        currency: Map.get(programme, :currency),
        cover_url: nil,
        url: PublicURL.base_url() <> "/b/#{slug}/programmes/#{programme.id}"
      }
    end)
  rescue
    _error -> []
  end
end
