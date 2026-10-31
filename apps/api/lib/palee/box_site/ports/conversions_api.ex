defmodule Palee.BoxSite.Ports.ConversionsApi do
  @moduledoc """
  ADR-354 §5: the server-side conversions endpoint of the box's ad platform
  (`config :palee, :box_site_conversions_api`). The token is the box's own,
  passed per call, and never logged.
  """

  @callback send_event(pixel_id :: String.t(), token :: String.t(), event :: map()) ::
              :ok | {:error, {:rejected, term()}} | {:error, {:transient, term()}}
end
