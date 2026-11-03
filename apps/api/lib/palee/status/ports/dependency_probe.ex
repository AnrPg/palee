defmodule Palee.Status.Ports.DependencyProbe do
  @moduledoc """
  ADR-364: checks every status page component once. Each result has the
  component key (`Palee.Status.Domain.Components`), `operational`,
  `degraded` or `down`, and an internal reason (never shown publicly).
  """

  @callback check() :: [
              %{component: String.t(), status: String.t(), reason: String.t() | nil}
            ]
end
