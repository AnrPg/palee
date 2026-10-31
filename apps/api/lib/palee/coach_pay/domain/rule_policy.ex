defmodule Palee.CoachPay.Domain.RulePolicy do
  @moduledoc """
  CP-A6 (ADR-341): what a coach pay rule may say, pure.

    * `per_class` – `amount_cents` for every class the coach ran, of the
      class types in `class_type_ids` (empty: every type), when at least
      `min_attendees` people counted;
    * `per_attendee` – `amount_cents` for every person counted in the
      coach's class, up to `max_attendees` per class;
    * `per_session` – `amount_cents` for every personal-training session
      or assessment the coach gave (at least one person attended);
    * `percent_of_sales` – `percent_bps` of the money attributed to the
      coach (`sales_scope`): `personal_training` (packages whose personal
      trainer is the coach) or `sold_by` (sales the coach recorded at the
      desk). A refund takes its share back (a clawback line).

  Who counts in a class (`count_statuses`): `attended` by default; a box
  may also pay for `late_cancel` and `no_show` (the place was held).
  """

  @kinds ~w(per_class per_attendee per_session percent_of_sales)
  @statuses ~w(attended late_cancel no_show)
  @scopes ~w(personal_training sold_by)
  @max_amount 10_000_000

  def kinds, do: @kinds
  def count_statuses, do: @statuses
  def sales_scopes, do: @scopes

  @doc """
  Checks and normalizes a new rule or a change (`current` is the stored
  rule, or `%{}`). Returns `{:ok, attrs}` or `{:error, {:invalid_fields, errors}}`.
  """
  def change(current, params) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    merged = Map.merge(stringify(current), params)
    kind = merged["kind"]

    errors =
      %{}
      |> check(kind in @kinds, "kind", "invalid")
      |> check(uuid?(merged["coach_user_id"]), "coach_user_id", "required")
      |> check(currency?(merged["currency"]), "currency", "invalid")
      |> check(match?(%Date{}, date(merged["starts_on"])), "starts_on", "required")
      |> check(
        is_nil(merged["ends_on"]) or
          (match?(%Date{}, date(merged["ends_on"])) and match?(%Date{}, date(merged["starts_on"])) and
             Date.compare(date(merged["ends_on"]), date(merged["starts_on"])) != :lt),
        "ends_on",
        "invalid"
      )
      |> check(
        is_list(merged["class_type_ids"] || []) and
          Enum.all?(merged["class_type_ids"] || [], &uuid?/1),
        "class_type_ids",
        "invalid"
      )
      |> check(
        is_list(merged["count_statuses"] || ["attended"]) and
          (merged["count_statuses"] || ["attended"]) != [] and
          Enum.all?(merged["count_statuses"] || ["attended"], &(&1 in @statuses)),
        "count_statuses",
        "invalid"
      )
      |> check(non_negative?(merged["min_attendees"] || 0, 1_000), "min_attendees", "invalid")
      |> check(
        is_nil(merged["max_attendees"]) or positive?(merged["max_attendees"], 1_000),
        "max_attendees",
        "invalid"
      )
      |> check(
        is_nil(merged["note"]) or
          (is_binary(merged["note"]) and String.length(merged["note"]) <= 200),
        "note",
        "invalid"
      )
      |> kind_errors(kind, merged)

    if errors == %{},
      do: {:ok, normalize(kind, merged)},
      else: {:error, {:invalid_fields, errors}}
  end

  def change(_current, _params), do: {:error, {:invalid_fields, %{"rule" => "invalid"}}}

  defp kind_errors(errors, "percent_of_sales", merged) do
    errors
    |> check(positive?(merged["percent_bps"], 10_000), "percent_bps", "invalid")
    |> check(merged["sales_scope"] in @scopes, "sales_scope", "invalid")
  end

  defp kind_errors(errors, kind, merged) when kind in @kinds,
    do: check(errors, positive?(merged["amount_cents"], @max_amount), "amount_cents", "invalid")

  defp kind_errors(errors, _kind, _merged), do: errors

  defp normalize("percent_of_sales" = kind, merged) do
    base(kind, merged)
    |> Map.merge(%{
      percent_bps: merged["percent_bps"],
      sales_scope: merged["sales_scope"],
      amount_cents: nil
    })
  end

  defp normalize(kind, merged) do
    base(kind, merged)
    |> Map.merge(%{amount_cents: merged["amount_cents"], percent_bps: nil, sales_scope: nil})
  end

  defp base(kind, merged) do
    %{
      kind: kind,
      coach_user_id: merged["coach_user_id"],
      currency: String.upcase(merged["currency"]),
      starts_on: date(merged["starts_on"]),
      ends_on: date(merged["ends_on"]),
      class_type_ids: (merged["class_type_ids"] || []) |> Enum.uniq() |> Enum.sort(),
      count_statuses: (merged["count_statuses"] || ["attended"]) |> Enum.uniq() |> Enum.sort(),
      min_attendees: merged["min_attendees"] || 0,
      max_attendees: merged["max_attendees"],
      note: merged["note"]
    }
  end

  @doc "Whether a rule pays for a day (its dates, inclusive)."
  def active_on?(rule, %Date{} = date) do
    Date.compare(rule.starts_on, date) != :gt and
      (is_nil(rule.ends_on) or Date.compare(rule.ends_on, date) != :lt)
  end

  @doc "The dates a rule keeps when archived on `today`: it pays nothing after today."
  def archive(rule, %Date{} = today) do
    ends_on =
      cond do
        Date.compare(rule.starts_on, today) == :gt -> rule.starts_on
        is_nil(rule.ends_on) or Date.compare(rule.ends_on, today) == :gt -> today
        true -> rule.ends_on
      end

    %{ends_on: ends_on}
  end

  defp check(errors, true, _field, _code), do: errors
  defp check(errors, _false, field, code), do: Map.put_new(errors, field, code)

  defp uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp uuid?(_value), do: false

  defp currency?(value) when is_binary(value), do: String.match?(value, ~r/^[A-Za-z]{3}$/)
  defp currency?(_value), do: false

  defp positive?(value, max), do: is_integer(value) and value > 0 and value <= max
  defp non_negative?(value, max), do: is_integer(value) and value >= 0 and value <= max

  defp date(%Date{} = date), do: date

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp date(_value), do: nil

  defp stringify(%{} = map),
    do:
      map
      |> Map.drop([:__struct__, :__meta__])
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
end
