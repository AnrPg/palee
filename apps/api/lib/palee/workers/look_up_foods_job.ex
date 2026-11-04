defmodule Palee.Workers.LookUpFoodsJob do
  @moduledoc """
  ADR-376: the barcode lookup outbox. Every few minutes it asks Open Food
  Facts for barcodes left pending (a slow or failed call, a product due for
  refresh). Claims are row-locked, so overlapping runs are safe.

  ADR-421 addendum: it also sends products members shared to Open Food
  Facts (at most 10 a run, so the read that checks the product first stays
  far below 15 reads a minute), when Palee's account there is configured.
  """

  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 60]

  alias Palee.Application.Foods

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _count} = Foods.process_due()
    {:ok, _shared} = Foods.process_shares()
    :ok
  end
end
