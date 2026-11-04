defmodule Palee.Application.BoxSite.SiteProgrammes do
  @moduledoc """
  ADR-530 §3 «Προγράμματα»: the programmes a box sells, as its website shows
  them (`%{id, title, summary, weeks, price_cents, currency, cover_url,
  url}` each). The section hides while the list is empty.

  TODO(ADR-530 §3): the public listing of programmes for sale does not
  exist yet; the programmes work fills `list/1` from it. Until then every
  box has none.
  """

  @doc "The box's programmes for sale, public fields only."
  @spec list(map()) :: [map()]
  def list(_context), do: []
end
