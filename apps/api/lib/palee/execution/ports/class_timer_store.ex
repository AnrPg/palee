defmodule Palee.Execution.Ports.ClassTimerStore do
  @moduledoc "ADR-746: one class timer per class and WOD (`workout_id` nil = a class without WOD)."
  @callback get_class_timer(map(), binary(), binary() | nil) :: map() | nil
  @callback list_class_timers(map(), binary()) :: [map()]
  @callback save_class_timer(map(), binary(), binary() | nil, map(), pos_integer() | nil) ::
              {:ok, map()} | {:error, :stale_class_timer} | {:error, Ecto.Changeset.t()}
end
