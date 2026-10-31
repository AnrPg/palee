defmodule Palee.Devices.Ports.WatchStore do
  @moduledoc """
  Persistence port of paired watches and their heart rate (ADR-375). Calls
  run inside the person's own RepoContext; row security admits only them.
  """

  alias Palee.Devices.{HeartRateBatch, WatchLink}

  @type id :: Ecto.UUID.t()

  @callback list_links(id()) :: [WatchLink.t()]
  @callback get_link(id(), String.t()) :: WatchLink.t() | nil
  @callback save_link(WatchLink.t() | nil, map()) :: {:ok, WatchLink.t()} | {:error, term()}
  @callback delete_link(id(), String.t()) :: non_neg_integer()
  @callback insert_heart_rate(id(), id(), [map()], DateTime.t()) :: {:ok, non_neg_integer()}
  @callback list_heart_rate(id()) :: [HeartRateBatch.t()]
end
