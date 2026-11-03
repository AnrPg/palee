defmodule Palee.Programmes.Domain.ProgrammePolicy do
  @moduledoc """
  The rules of a programme a box or a coach sells (ADR-370), pure.

      draft ─publish─► published ─archive─► archived ─publish─► published

    * A programme is written as days: `%{"day" => 0.., "workout_id" => id}`
      within `weeks`; at most #{4} WODs on one day.
    * Publishing freezes the days into a new version (`ProgrammeVersion`):
      buyers keep the version they bought; a later version reaches only
      later buyers. Title, summary, price and listing change without a
      version; the days never change in place.
    * Only a paid programme (price above 0) is sold; `listing` says where
      it is shown: `box` (the seller's own page and members) or
      `marketplace` (also the cross-business catalogue).
    * `preview_days`: how many first days anyone may look at before buying.
  """

  @statuses ~w(draft published archived)
  @listings ~w(box marketplace)
  @levels ~w(all beginner intermediate advanced)
  @goals ~w(general strength conditioning gymnastics weightlifting endurance competition hyrox
            mobility)
  @refund_policies ~w(before_start withdrawal_only pro_rata)
  @currencies ~w(EUR GBP USD CHF)
  @max_per_day 4
  @max_weeks 52
  @max_preview_days 14
  @max_price_cents 10_000_000

  def statuses, do: @statuses
  def listings, do: @listings
  def levels, do: @levels
  def goals, do: @goals
  def refund_policies, do: @refund_policies
  def currencies, do: @currencies
  def max_weeks, do: @max_weeks
  def max_preview_days, do: @max_preview_days
  def max_price_cents, do: @max_price_cents
  def max_per_day, do: @max_per_day

  @doc """
  Normalises and checks the days of a draft against `weeks`:
  `{:ok, [%{"day" => integer, "workout_id" => id}]}` sorted by day, or
  `{:error, :invalid_programme_days}`.
  """
  def normalize_days(days, weeks) when is_list(days) and is_integer(weeks) do
    with true <- weeks in 1..@max_weeks,
         {:ok, rows} <- rows(days, weeks * 7),
         true <- rows != [],
         true <- length(Enum.uniq(rows)) == length(rows),
         true <-
           Enum.all?(Enum.frequencies_by(rows, & &1["day"]), fn {_, n} -> n <= @max_per_day end) do
      {:ok, Enum.sort_by(rows, &{&1["day"], &1["workout_id"]})}
    else
      _invalid -> {:error, :invalid_programme_days}
    end
  end

  def normalize_days(_days, _weeks), do: {:error, :invalid_programme_days}

  defp rows(days, length) do
    Enum.reduce_while(days, {:ok, []}, fn row, {:ok, acc} ->
      day = row["day"] || row[:day]
      workout_id = row["workout_id"] || row[:workout_id]

      if is_integer(day) and day >= 0 and day < length and uuid?(workout_id),
        do: {:cont, {:ok, [%{"day" => day, "workout_id" => workout_id} | acc]}},
        else: {:halt, :error}
    end)
  end

  defp uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp uuid?(_value), do: false

  @doc "The ids of the WODs a draft's days use, in order and once each."
  def workout_ids(days), do: days |> Enum.map(& &1["workout_id"]) |> Enum.uniq()

  @doc """
  Whether a programme may be published with `days` (the draft's or the
  current version's): `:ok` or the first reason it may not.
  """
  def publishable(programme, days) do
    cond do
      programme.status == "published" and days == :unchanged ->
        {:error, :programme_already_published}

      not (is_integer(programme.price_cents) and programme.price_cents > 0) ->
        {:error, :programme_price_required}

      programme.currency not in @currencies ->
        {:error, :unsupported_currency}

      days == [] ->
        {:error, :invalid_programme_days}

      true ->
        :ok
    end
  end

  @doc "A lifecycle step: `{:ok, changes}` or `{:error, reason}`."
  def transition(%{status: "published"}, :archive, now),
    do: {:ok, %{status: "archived", archived_at: now}}

  def transition(%{status: "archived", current_version_id: id}, :restore, _now)
      when is_binary(id),
      do: {:ok, %{status: "published", archived_at: nil}}

  def transition(_programme, _step, _now), do: {:error, :invalid_programme_transition}

  @doc "Whether people can see and buy it (published, paid)."
  def on_sale?(%{status: "published", price_cents: cents, current_version_id: id})
      when is_integer(cents) and cents > 0 and is_binary(id),
      do: true

  def on_sale?(_programme), do: false

  @doc "Whether the programme shows in the cross-business catalogue."
  def in_marketplace?(programme), do: on_sale?(programme) and programme.listing == "marketplace"

  @doc """
  The days anyone may see before buying: those before `preview_days`
  (WOD ids and titles only; the WOD itself opens after purchase).
  """
  def preview(days, preview_days) when is_list(days) and is_integer(preview_days),
    do: Enum.filter(days, &(&1["day"] < preview_days))

  def preview(_days, _preview_days), do: []
end
