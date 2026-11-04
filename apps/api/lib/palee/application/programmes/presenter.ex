defmodule Palee.Application.Programmes.Presenter do
  @moduledoc """
  Projections of programmes for staff, buyers and the public (ADR-370).
  The public never sees the WODs of a programme beyond its preview days,
  nor the buyers.
  """

  @public_fields ~w(id title summary description level goal equipment sessions_per_week
                    price_cents currency listing preview_days refund_policy published_at)a

  @staff_fields @public_fields ++
                  ~w(status draft_weeks draft_days current_version_id archived_at author_id
                     inserted_at updated_at)a

  def staff(programme, extra \\ %{}),
    do: programme |> Map.take(@staff_fields) |> Map.merge(extra)

  def public(programme, version, extra \\ %{}) do
    programme
    |> Map.take(@public_fields)
    |> Map.merge(%{
      weeks: version && version.weeks,
      version_number: version && version.number,
      sessions: version && length(version.days)
    })
    |> Map.merge(extra)
  end

  def version(version) do
    Map.take(version, [:id, :number, :weeks, :days, :changelog, :published_at, :published_by_id])
  end

  @doc "Preview days: day, week, weekday, the WOD's title and summary only."
  def preview_days(days) do
    Enum.map(days, fn row ->
      %{
        day: row["day"],
        week: div(row["day"], 7) + 1,
        weekday: rem(row["day"], 7),
        title: row["title"],
        summary: row["summary"]
      }
    end)
  end

  def purchase(purchase, extra \\ %{}) do
    purchase
    |> Map.take([
      :id,
      :programme_id,
      :version_id,
      :user_id,
      :status,
      :price_cents,
      :currency,
      :refund_policy,
      :starts_on,
      :ends_on,
      :payment_intent_id,
      :refunded_cents,
      :activated_at,
      :ended_at,
      :end_reason,
      :inserted_at
    ])
    |> Map.put(:withdrawal_deadline, get_in(purchase.withdrawal || %{}, ["deadline"]))
    |> Map.merge(extra)
  end

  def review(review, author \\ nil) do
    review
    |> Map.take([
      :id,
      :rating,
      :body,
      :status,
      :hidden_reason,
      :version_number,
      :inserted_at,
      :updated_at
    ])
    |> Map.put(:author, author)
  end
end
