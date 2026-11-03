defmodule Palee.Status.Ports.Clock do
  @moduledoc "The time the status page reads (ADR-364); tests fix it."

  @callback now() :: DateTime.t()
end
