defmodule Palee.Analytics.Domain.AnalyticsFilter do
  @moduledoc """
  The one filter every staff analytics summary takes (ADR-462 §1): the
  reporting period and the dimensions that narrow it. Parsed and validated
  at the controller edge (`Analytics.parse_analytics_filter/2`), then handed
  to the single query-composition module in infrastructure (`FilterQuery`),
  so every metric shares one filter implementation.

  Period: `from`/`to` are gym-local dates (ADR-176/179), both included.
  Without them `days` (kept for backwards compatibility, default 30) ends
  the period today. The previous period is the one of equal length that
  ends the day before `from`; every KPI is returned for both.

  Dimensions:

    * class facts: `location_ids`, `class_type_ids`, `levels` (the class
      type's difficulty), `coach_ids`, `time_of_day` (gym-local start hour);
    * people: `package_families`, `package_ids`, `tenure_bands` (from the
      box membership's `joined_at`), and the opt-in only `age_bands` and
      `genders` (from the person's leaderboard opt-in row, ADR-356; Palee
      never collects a date of birth, ADR-267). Each of those two also
      takes `unknown`: the people who did not give one.

  Any figure built from an age or gender selection, and any age or gender
  bucket, covering fewer than `KAnonymity.threshold/0` people is
  suppressed (`KAnonymity`).
  """

  alias Palee.Identity.Domain.FilterFields

  @default_days 30
  @max_days 731
  @levels ~w(beginner all_levels advanced)
  @times_of_day ~w(morning midday afternoon evening)
  @tenure_bands ~w(lt_3m 3_12m gt_12m)
  @age_bands ~w(under_18 18_34 35_44 45_54 55_64 65_plus unknown)
  @genders ~w(women men unknown)
  @max_ids 200
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @family ~r/\A[a-z0-9_\-]{1,40}\z/

  # Gym-local start hours, [from, to).
  @time_of_day_hours %{
    "morning" => {0, 11},
    "midday" => {11, 14},
    "afternoon" => {14, 17},
    "evening" => {17, 24}
  }

  defstruct from: nil,
            to: nil,
            days: @default_days,
            location_ids: [],
            class_type_ids: [],
            levels: [],
            coach_ids: [],
            time_of_day: [],
            package_families: [],
            package_ids: [],
            tenure_bands: [],
            age_bands: [],
            genders: []

  @type t :: %__MODULE__{}

  def levels, do: @levels
  def times_of_day, do: @times_of_day
  def tenure_bands, do: @tenure_bands
  def age_bands, do: @age_bands
  def genders, do: @genders
  def max_days, do: @max_days

  @doc "Gym-local `[from, to)` start hours of a time-of-day bucket."
  def time_of_day_hours(bucket), do: Map.fetch!(@time_of_day_hours, bucket)

  @doc """
  Parses query params into a filter; `today` is the gym's local date.
  Unknown values are refused with `{:error, [field: message]}`.
  """
  def parse(params, %Date{} = today) when is_map(params) do
    params = FilterFields.stringify(params)

    with {:ok, {from, to, days}} <- period(params, today),
         {:ok, location_ids} <- ids(:location_ids, params["location_ids"]),
         {:ok, class_type_ids} <- ids(:class_type_ids, params["class_type_ids"]),
         {:ok, coach_ids} <- ids(:coach_ids, params["coach_ids"]),
         {:ok, package_ids} <- ids(:package_ids, params["package_ids"]),
         {:ok, levels} <- FilterFields.subset(:levels, params["levels"], @levels),
         {:ok, times} <- FilterFields.subset(:time_of_day, params["time_of_day"], @times_of_day),
         {:ok, tenure} <-
           FilterFields.subset(:tenure_bands, params["tenure_bands"], @tenure_bands),
         {:ok, ages} <- FilterFields.subset(:age_bands, params["age_bands"], @age_bands),
         {:ok, genders} <- FilterFields.subset(:genders, params["genders"], @genders),
         {:ok, families} <- families(params["package_families"]) do
      {:ok,
       %__MODULE__{
         from: from,
         to: to,
         days: days,
         location_ids: location_ids,
         class_type_ids: class_type_ids,
         levels: levels,
         coach_ids: coach_ids,
         time_of_day: times,
         package_families: families,
         package_ids: package_ids,
         tenure_bands: tenure,
         age_bands: ages,
         genders: genders
       }}
    end
  end

  def parse(_params, today), do: parse(%{}, today)

  @doc "The filter over the previous period of equal length."
  def previous(%__MODULE__{from: from, days: days} = filter) do
    to = Date.add(from, -1)
    %{filter | from: Date.add(to, -(days - 1)), to: to}
  end

  @doc "Narrows the branches to `ids` (the staff member's branch scope)."
  def put_locations(%__MODULE__{} = filter, :all), do: filter

  def put_locations(%__MODULE__{} = filter, ids) when is_list(ids),
    do: %{filter | location_ids: ids}

  @doc "True when a dimension narrows the people a figure counts."
  def people_filtered?(%__MODULE__{} = filter),
    do:
      filter.package_families != [] or filter.package_ids != [] or filter.tenure_bands != [] or
        demographic?(filter)

  @doc "True when an opt-in demographic (age or gender) narrows the people."
  def demographic?(%__MODULE__{age_bands: ages, genders: genders}),
    do: ages != [] or genders != []

  @doc "True when a dimension narrows class facts."
  def classes_filtered?(%__MODULE__{} = filter),
    do:
      filter.location_ids != [] or filter.class_type_ids != [] or filter.levels != [] or
        filter.coach_ids != [] or filter.time_of_day != []

  @doc "The age band of a birth year in the year of `on`."
  def age_band(nil, _on), do: "unknown"

  def age_band(birth_year, %Date{year: year}) when is_integer(birth_year) do
    case year - birth_year do
      age when age < 18 -> "under_18"
      age when age < 35 -> "18_34"
      age when age < 45 -> "35_44"
      age when age < 55 -> "45_54"
      age when age < 65 -> "55_64"
      _age -> "65_plus"
    end
  end

  @doc "Birth years `{min, max}` of an age band in the year of `on` (nil for unknown)."
  def birth_years("unknown", _on), do: nil
  def birth_years("under_18", %Date{year: y}), do: {y - 17, 2100}
  def birth_years("18_34", %Date{year: y}), do: {y - 34, y - 18}
  def birth_years("35_44", %Date{year: y}), do: {y - 44, y - 35}
  def birth_years("45_54", %Date{year: y}), do: {y - 54, y - 45}
  def birth_years("55_64", %Date{year: y}), do: {y - 64, y - 55}
  def birth_years("65_plus", %Date{year: y}), do: {1900, y - 65}

  @doc "The tenure band of a person who joined on `joined_on`, as of `on`."
  def tenure_band(%Date{} = joined_on, %Date{} = on) do
    cond do
      Date.compare(joined_on, Date.shift(on, month: -3)) == :gt -> "lt_3m"
      Date.compare(joined_on, Date.shift(on, month: -12)) == :gt -> "3_12m"
      true -> "gt_12m"
    end
  end

  @doc "The `joined_on` dates `{after, on_or_before}` a tenure band covers, as of `on` (nil = open)."
  def joined_between("lt_3m", on), do: {Date.shift(on, month: -3), nil}
  def joined_between("3_12m", on), do: {Date.shift(on, month: -12), Date.shift(on, month: -3)}
  def joined_between("gt_12m", on), do: {nil, Date.shift(on, month: -12)}

  @doc "The applied filter, echoed by a response (`v` 1)."
  def to_params(%__MODULE__{} = filter) do
    previous = previous(filter)

    %{
      v: 1,
      from: Date.to_iso8601(filter.from),
      to: Date.to_iso8601(filter.to),
      days: filter.days,
      previous_from: Date.to_iso8601(previous.from),
      previous_to: Date.to_iso8601(previous.to),
      location_ids: filter.location_ids,
      class_type_ids: filter.class_type_ids,
      levels: filter.levels,
      coach_ids: filter.coach_ids,
      time_of_day: filter.time_of_day,
      package_families: filter.package_families,
      package_ids: filter.package_ids,
      tenure_bands: filter.tenure_bands,
      age_bands: filter.age_bands,
      genders: filter.genders
    }
  end

  defp period(params, today) do
    with {:ok, from} <- FilterFields.date(:from, params["from"]),
         {:ok, to} <- FilterFields.date(:to, params["to"]),
         {:ok, days} <- days(params["days"]) do
      case {from, to} do
        {nil, nil} -> {:ok, {Date.add(today, -(days - 1)), today, days}}
        {nil, to} -> span(Date.add(to, -(days - 1)), to)
        {from, nil} -> span(from, max_date(from, today))
        {from, to} -> span(from, to)
      end
    end
  end

  defp max_date(a, b), do: if(Date.compare(a, b) == :gt, do: a, else: b)

  defp span(from, to) do
    days = Date.diff(to, from) + 1

    cond do
      days < 1 -> {:error, [to: "must not be before from"]}
      days > @max_days -> {:error, [to: "the period is at most #{@max_days} days"]}
      true -> {:ok, {from, to, days}}
    end
  end

  defp days(nil), do: {:ok, @default_days}
  defp days(""), do: {:ok, @default_days}
  defp days(days) when is_integer(days) and days >= 1 and days <= 365, do: {:ok, days}

  defp days(days) when is_binary(days) do
    case Integer.parse(days) do
      {value, ""} -> days(value)
      _invalid -> {:error, [days: "must be a whole number from 1 to 365"]}
    end
  end

  defp days(_days), do: {:error, [days: "must be a whole number from 1 to 365"]}

  defp ids(field, value) do
    case FilterFields.list(value) do
      {:ok, values} ->
        values = values |> Enum.map(&normalize/1) |> Enum.uniq()

        cond do
          length(values) > @max_ids -> {:error, [{field, "at most #{@max_ids}"}]}
          Enum.all?(values, &(is_binary(&1) and &1 =~ @uuid)) -> {:ok, Enum.sort(values)}
          true -> {:error, [{field, "must be ids"}]}
        end

      :error ->
        {:error, [{field, "must be a list"}]}
    end
  end

  defp families(value) do
    case FilterFields.list(value) do
      {:ok, values} ->
        values = values |> Enum.map(&normalize/1) |> Enum.uniq()

        if length(values) <= @max_ids and Enum.all?(values, &(is_binary(&1) and &1 =~ @family)),
          do: {:ok, Enum.sort(values)},
          else: {:error, [package_families: "has an unknown value"]}

      :error ->
        {:error, [package_families: "must be a list"]}
    end
  end

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(value), do: value
end
