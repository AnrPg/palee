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
  @doc """
  ADR-382: coaching relations (ADR-100) that held in the period, as
  gym-local days: `%{coach_user_id, client_user_id, from, to}` (`to` nil
  while it holds).
  """
  @callback coach_clients(context(), Date.t(), Date.t()) :: [map()]
  @doc "ADR-382: each staff member's pay-item roles (`%{user_id => [role]}`)."
  @callback staff_roles(context()) :: %{optional(String.t()) => [String.t()]}
end
