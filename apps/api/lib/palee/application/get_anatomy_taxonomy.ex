defmodule Palee.Application.GetAnatomyTaxonomy do
  @moduledoc """
  The anatomy taxonomy for clients (ADR-163): version, nodes, fitness
  qualities and goal roles, with a strong ETag derived from the content so
  clients and proxies can cache it until it changes. ADR-560: it is read
  from the reference catalog copy, so the ETag follows the tables.
  """

  alias Palee.Anatomy

  def call do
    taxonomy = Anatomy.taxonomy()

    etag =
      ~s("anatomy-v#{taxonomy.version}-) <>
        (:crypto.hash(:sha256, :erlang.term_to_binary(taxonomy))
         |> Base.url_encode64(padding: false)
         |> binary_part(0, 16)) <> ~s(")

    {:ok, taxonomy, etag}
  end
end
