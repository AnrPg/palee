defmodule Palee.Gamification.Domain.LeaderboardFilters do
  @moduledoc """
  ADR-356 (CP-D2): the filters of a WOD's leaderboard and who passes them.

    * `division` – `women` or `men`, as the person told the box when they
      opted in (nothing said: they show only when no division is chosen);
    * `age_group` – masters-style groups from the birth year, by the age
      reached during the year of the result (`age_in/2`);
    * `scale` – a scale level slug of the box (`rx`, `scaled`, …);
    * `scope` – `box` (every branch), `branch` (people whose home branch
      is `location_id`) or `palee` (ADR-394: every box, for a WOD tagged
      as a benchmark, only people who agreed to the Palee-wide board);
    * `window` – `day`, `week`, `month`, `year` or `all`, anchored on a gym
      date (`window/3`);
    * `buddies` – only the viewer and their buddies.

  Pure: the application reads people, results and dates and asks
  `keep?/2` for each person.
  """

  @divisions ~w(women men)
  @age_groups ~w(under_18 18_34 35_39 40_44 45_49 50_54 55_59 60_64 65_plus)
  @scopes ~w(box branch palee)
  @windows ~w(day week month year all)

  @enforce_keys [:window, :scope]
  defstruct division: nil,
            age_group: nil,
            scale: nil,
            scope: "box",
            location_id: nil,
            window: "day",
            date: nil,
            buddies: false

  @type t :: %__MODULE__{
          division: String.t() | nil,
          age_group: String.t() | nil,
          scale: String.t() | nil,
          scope: String.t(),
          location_id: String.t() | nil,
          window: String.t(),
          date: Date.t() | nil,
          buddies: boolean()
        }

  @type person :: %{
          optional(:division) => String.t() | nil,
          optional(:birth_year) => integer() | nil,
          optional(:scale_level_slug) => String.t() | nil,
          optional(:home_location_id) => String.t() | nil,
          optional(:buddy?) => boolean()
        }

  def divisions, do: @divisions
  def age_groups, do: @age_groups
  def scopes, do: @scopes
  def windows, do: @windows

  @doc """
  Reads the query. Blank values mean «all». `scope=branch` needs a
  `location_id`. `{:error, {:invalid_leaderboard_filter, field}}` names the
  first field that does not read.
  """
  @spec parse(map()) :: {:ok, t()} | {:error, {:invalid_leaderboard_filter, atom()}}
  def parse(params) when is_map(params) do
    with {:ok, division} <- one_of(params, :division, @divisions),
         {:ok, age_group} <- one_of(params, :age_group, @age_groups),
         {:ok, scope} <- one_of(params, :scope, @scopes),
         {:ok, window} <- one_of(params, :window, @windows),
         {:ok, date} <- date(param(params, :date)),
         {:ok, buddies} <- boolean(param(params, :buddies)),
         {:ok, scale} <- scale(param(params, :scale)),
         location_id = blank_to_nil(param(params, :location_id)),
         :ok <- branch_needs_location(scope, location_id),
         :ok <- palee_without_buddies(scope, buddies) do
      {:ok,
       %__MODULE__{
         division: division,
         age_group: age_group,
         scale: scale,
         scope: scope || "box",
         location_id: if(scope == "branch", do: location_id),
         window: window || "day",
         date: date,
         buddies: buddies
       }}
    end
  end

  def parse(_params), do: parse(%{})

  @doc "Whether a person's result passes every filter except the window."
  @spec keep?(t(), person(), integer()) :: boolean()
  def keep?(%__MODULE__{} = filters, person, year) do
    division?(filters.division, Map.get(person, :division)) and
      age?(filters.age_group, Map.get(person, :birth_year), year) and
      scale?(filters.scale, Map.get(person, :scale_level_slug)) and
      branch?(filters, Map.get(person, :home_location_id)) and
      (not filters.buddies or Map.get(person, :buddy?, false))
  end

  @doc """
  ADR-394: whether a Palee-wide row passes the division, age group and scale
  filters. The row carries its `division` and `age_group` as the person's
  box told them (the age group already reckoned for the board's year).
  """
  @spec keep_palee?(t(), map()) :: boolean()
  def keep_palee?(%__MODULE__{} = filters, row) do
    division?(filters.division, Map.get(row, :division)) and
      (is_nil(filters.age_group) or filters.age_group == Map.get(row, :age_group)) and
      scale?(filters.scale, Map.get(row, :scale_level_slug))
  end

  @doc "The age a person born in `birth_year` reaches during `year`."
  def age_in(birth_year, year) when is_integer(birth_year) and is_integer(year),
    do: year - birth_year

  @doc "The age group of an age, or nil without a birth year."
  def age_group(nil, _year), do: nil

  def age_group(birth_year, year) when is_integer(birth_year) do
    case age_in(birth_year, year) do
      age when age < 18 -> "under_18"
      age when age < 35 -> "18_34"
      age when age >= 65 -> "65_plus"
      age -> group_of(age)
    end
  end

  defp group_of(age) do
    low = div(age, 5) * 5
    "#{low}_#{low + 4}"
  end

  @doc """
  `{from, to}` local dates (to exclusive) of the window around `date`:
  the day, its ISO week (Monday first), its month, its year; `all` is nil.
  """
  @spec window(String.t(), Date.t()) :: {Date.t(), Date.t()} | nil
  def window("day", date), do: {date, Date.add(date, 1)}

  def window("week", date) do
    monday = Date.add(date, 1 - Date.day_of_week(date))
    {monday, Date.add(monday, 7)}
  end

  def window("month", date) do
    first = Date.beginning_of_month(date)
    {first, date |> Date.end_of_month() |> Date.add(1)}
  end

  def window("year", date), do: {Date.new!(date.year, 1, 1), Date.new!(date.year + 1, 1, 1)}
  def window("all", _date), do: nil

  @doc "The applied filters, as the API returns them."
  def present(%__MODULE__{} = filters) do
    %{
      division: filters.division,
      age_group: filters.age_group,
      scale: filters.scale,
      scope: filters.scope,
      location_id: filters.location_id,
      window: filters.window,
      date: filters.date,
      buddies: filters.buddies
    }
  end

  defp division?(nil, _division), do: true
  defp division?(wanted, division), do: wanted == division

  defp age?(nil, _birth_year, _year), do: true
  defp age?(wanted, birth_year, year), do: age_group(birth_year, year) == wanted

  defp scale?(nil, _slug), do: true
  defp scale?(wanted, slug), do: wanted == slug

  defp branch?(%__MODULE__{scope: "branch", location_id: location_id}, home),
    do: home == location_id

  defp branch?(_filters, _home), do: true

  defp one_of(params, key, allowed) do
    case blank_to_nil(param(params, key)) do
      nil -> {:ok, nil}
      value when is_binary(value) -> if value in allowed, do: {:ok, value}, else: invalid(key)
      _other -> invalid(key)
    end
  end

  defp scale(value) do
    case blank_to_nil(value) do
      nil ->
        {:ok, nil}

      slug when is_binary(slug) and byte_size(slug) <= 64 ->
        {:ok, slug}

      _other ->
        invalid(:scale)
    end
  end

  defp date(value) do
    case blank_to_nil(value) do
      nil ->
        {:ok, nil}

      %Date{} = date ->
        {:ok, date}

      text when is_binary(text) ->
        case Date.from_iso8601(text) do
          {:ok, date} -> {:ok, date}
          _invalid -> invalid(:date)
        end

      _other ->
        invalid(:date)
    end
  end

  defp boolean(value) when value in [true, "true", "1"], do: {:ok, true}
  defp boolean(value) when value in [nil, false, "", "false", "0"], do: {:ok, false}
  defp boolean(_value), do: invalid(:buddies)

  # Buddies are people of one's own box; the Palee-wide board has none.
  defp palee_without_buddies("palee", true), do: invalid(:buddies)
  defp palee_without_buddies(_scope, _buddies), do: :ok

  defp branch_needs_location("branch", nil), do: invalid(:location_id)
  defp branch_needs_location(_scope, _location_id), do: :ok

  defp invalid(field), do: {:error, {:invalid_leaderboard_filter, field}}

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
