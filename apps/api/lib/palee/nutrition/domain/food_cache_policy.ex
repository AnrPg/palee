defmodule Palee.Nutrition.Domain.FoodCachePolicy do
  @moduledoc """
  How long a looked-up barcode is trusted and how lookups are retried
  (ADR-376). The cache is also the outbox of lookups (`pending` rows):

    * a found product is served for 30 days, then still served while a
      refresh is queued (Open Food Facts changes slowly);
    * "not in Open Food Facts" is believed for 7 days, so a new product
      added there later is found;
    * a failed call is retried after 1, 5, 30 minutes, then hourly, up to
      6 attempts; then `failed` until someone scans it again a day later;
    * a claim older than 2 minutes is taken over (a crashed worker).

  Attribution travels with every product shown (ODbL §4.3): the source,
  its licence and a link to the product page.
  """

  @found_ttl_days 30
  @not_found_ttl_days 7
  @failed_ttl_hours 24
  @max_attempts 6
  @claim_timeout_seconds 120
  @backoff_minutes [1, 5, 30, 60, 60, 60]

  def max_attempts, do: @max_attempts
  def claim_timeout_seconds, do: @claim_timeout_seconds

  @doc """
  What to do with a cache row at `now`: `:serve`, `{:serve, :refresh}`,
  `:wait` (a lookup is pending) or `:lookup` (none, or expired).
  """
  def decide(nil, _now), do: :lookup

  def decide(%{status: "found", fetched_at: fetched_at}, now) do
    if older_than?(fetched_at, now, @found_ttl_days * 86_400),
      do: {:serve, :refresh},
      else: :serve
  end

  def decide(%{status: "not_found", fetched_at: fetched_at}, now) do
    if older_than?(fetched_at, now, @not_found_ttl_days * 86_400), do: :lookup, else: :serve
  end

  def decide(%{status: "failed", updated_at: updated_at}, now) do
    if older_than?(updated_at, now, @failed_ttl_hours * 3600), do: :lookup, else: :serve
  end

  def decide(%{status: "pending"}, _now), do: :wait

  @doc "The row's changes after a lookup outcome at `now` (`attempts` already counts this one)."
  def after_lookup({:ok, attrs}, _row, now),
    do:
      Map.merge(attrs, %{
        status: "found",
        fetched_at: now,
        next_attempt_at: nil,
        claimed_at: nil,
        attempts: 0,
        last_error: nil
      })

  def after_lookup({:error, :not_found}, _row, now),
    do: %{
      status: "not_found",
      fetched_at: now,
      next_attempt_at: nil,
      claimed_at: nil,
      attempts: 0,
      last_error: nil
    }

  def after_lookup({:error, reason}, row, now) do
    attempts = row.attempts || 1

    if attempts >= @max_attempts do
      %{
        status: failed_status(row),
        next_attempt_at: nil,
        claimed_at: nil,
        last_error: describe(reason)
      }
    else
      minutes = Enum.at(@backoff_minutes, attempts - 1, 60)

      %{
        status: "pending",
        next_attempt_at: DateTime.add(now, minutes * 60, :second),
        claimed_at: nil,
        last_error: describe(reason)
      }
    end
  end

  # A product already found stays found (served stale) when a refresh fails.
  defp failed_status(%{name: name}) when is_binary(name), do: "found"
  defp failed_status(_row), do: "failed"

  defp describe(reason), do: reason |> inspect() |> String.slice(0, 200)

  defp older_than?(nil, _now, _seconds), do: true
  defp older_than?(at, now, seconds), do: DateTime.diff(now, at, :second) > seconds

  @doc "The attribution shown with a product from Open Food Facts."
  def attribution(barcode) do
    %{
      source: "Open Food Facts",
      licence: "ODbL-1.0",
      licence_url: "https://opendatacommons.org/licenses/odbl/1-0/",
      images_licence: "CC BY-SA 3.0",
      url: "https://world.openfoodfacts.org/product/" <> barcode
    }
  end
end
