defmodule Palee.DataQuestions.Ports.BoxDataReader do
  @moduledoc """
  Runs one catalogue query (ADR-361) for the box in the tenant context,
  under its row-level security, with arguments already validated and
  resolved by `Domain.Catalogue` (periods as gym-local dates). `zone` is
  the gym's time zone, for turning stored instants into local days.

  Returns `%{summary: map, rows: [map]}` with string keys. Money is in
  `*_cents` integer fields; people rows carry `user_id` and `name`, which
  never reach the model (`Domain.ResultShape`). At most 100 rows.
  """

  @callback run(context :: map(), query :: String.t(), params :: map(), zone :: String.t()) ::
              {:ok, %{summary: map(), rows: [map()]}} | {:error, term()}
end
