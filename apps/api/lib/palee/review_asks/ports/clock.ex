defmodule Palee.ReviewAsks.Ports.Clock do
  @moduledoc "The time review asks run on (`config :palee, :review_ask_clock`)."

  @callback now() :: DateTime.t()
end
