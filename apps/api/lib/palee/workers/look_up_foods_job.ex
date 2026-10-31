defmodule Palee.Workers.LookUpFoodsJob do
  @moduledoc """
  ADR-376: the barcode lookup outbox. Every few minutes it asks Open Food
  Facts for barcodes left pending (a slow or failed call, a product due for
  refresh). Claims are row-locked, so overlapping runs are safe.
  """

  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 60]

  alias Palee.Application.Foods

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _count} = Foods.process_due()
    :ok
  end
end
