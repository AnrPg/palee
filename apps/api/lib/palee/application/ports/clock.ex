defmodule Palee.Application.Ports.Clock do
  @moduledoc """
  The time application services read (ADR-043 §5), for the v3.2 body and
  devices services (ADR-374..377); tests fix it.
  """

  @callback now() :: DateTime.t()
end
