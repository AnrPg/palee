defmodule Palee.Programmes.Ports.Catalogue do
  @moduledoc """
  The cross-business programme catalogue (ADR-370): public fields of
  published, marketplace-listed programmes of every active business. The
  adapter reads only through a projection that exposes nothing else (the
  `palee_marketplace_programmes` SECURITY DEFINER function), so it needs no
  tenant context.

  `filters`: `query`, `goal`, `level`, `limit`, `offset`.
  """

  @callback search(map()) :: [map()]
end
