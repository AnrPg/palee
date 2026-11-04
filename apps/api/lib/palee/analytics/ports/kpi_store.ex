defmodule Palee.Analytics.Ports.KpiStore do
  @moduledoc "ADR-462: the staff KPIs over one filter scope."

  @callback scope(struct(), String.t(), {DateTime.t(), DateTime.t()}, [String.t()] | nil) ::
              map()
  @callback compute(String.t(), map()) :: %{value: term(), rows: [map()]}
  @callback cohort_size(map()) :: non_neg_integer() | nil
  @callback people_ids(map()) :: [String.t()] | nil
end
