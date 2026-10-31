defmodule Palee.CoachPay.Ports.Clock do
  @moduledoc """
  The time coach pay runs on (ADR-341), injected so tests can stand at any
  day of a period. Chosen in config (`:coach_pay_clock`).
  """

  @callback now() :: DateTime.t()
end
