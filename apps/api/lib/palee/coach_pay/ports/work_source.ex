defmodule Palee.CoachPay.Ports.WorkSource do
  @moduledoc """
  What coach pay reads from the rest of Palee (ADR-341): the classes and
  sessions the coaches ran (Scheduling, Appointments) and the money
  attributed to them (Finance revenue lineage, ADR-192), for gym-local
  dates. Read only. The shapes are `Palee.CoachPay.Domain.PayCalculator`'s.
  """

  @type context :: map()

  @callback classes(context(), Date.t(), Date.t()) :: [map()]
  @callback sessions(context(), Date.t(), Date.t()) :: [map()]
  @callback sales(context(), Date.t(), Date.t()) :: [map()]
end
