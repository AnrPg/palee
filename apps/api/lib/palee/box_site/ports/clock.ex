defmodule Palee.BoxSite.Ports.Clock do
  @moduledoc "The time the website services run on (`config :palee, :box_site_clock`)."

  @callback now() :: DateTime.t()
end
