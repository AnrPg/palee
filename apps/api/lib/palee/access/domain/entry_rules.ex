defmodule Palee.Access.Domain.EntryRules do
  @moduledoc """
  Who may open a door and when (ADR-381). One pure decision, in this order:

    1. **Staff** of the box (owner, admin, coach, front desk) open any door
       of a branch they work at, at any hour, unless the owner turned that
       off for the door.
    2. A person who is **not an active member** never opens it
       (`not_a_member`): visitors go to the desk.
    3. Outside the door's **opening hours** (the box's own time zone)
       members are refused (`outside_hours`).
    4. Who the door admits:
       * `booked_or_covered` (default, the calm one): a booking at this
         branch whose class starts within the window (30′ before to 15′
         after its start by default), or a package that covers open gym
         now;
       * `members`: every active member (24/7 boxes);
       * `staff_only`: only staff (a storeroom, an office).

  Pure: the caller gathers facts and passes the local time.
  """

  @whos ~w(booked_or_covered members staff_only)
  @defaults %{
    "who" => "booked_or_covered",
    "staff_always" => true,
    "window_before_minutes" => 30,
    "window_after_minutes" => 15,
    "unlock_seconds" => 5,
    "hours" => []
  }

  def whos, do: @whos
  def defaults, do: @defaults

  @type facts :: %{
          staff?: boolean(),
          member?: boolean(),
          bookings: [map()],
          open_gym_covered?: boolean(),
          location_id: String.t()
        }

  @doc """
  `{:grant, reason}` or `{:deny, reason}`. `now` is UTC (booking windows),
  `local` the box's local `NaiveDateTime` (opening hours).
  """
  def decide(facts, rules, %DateTime{} = now, %NaiveDateTime{} = local) do
    rules = Map.merge(@defaults, rules || %{})

    cond do
      facts.staff? and rules["staff_always"] == true -> {:grant, :staff}
      not facts.member? -> {:deny, :not_a_member}
      not within_hours?(rules["hours"], local) -> {:deny, :outside_hours}
      rules["who"] == "staff_only" -> {:deny, :staff_only}
      rules["who"] == "members" -> {:grant, :member}
      booked_in_window?(facts, rules, now) -> {:grant, :booked_class}
      facts.open_gym_covered? -> {:grant, :open_gym}
      true -> {:deny, :no_booking_in_window}
    end
  end

  @doc "A booking at the door's branch whose class starts within the window."
  def booked_in_window?(facts, rules, now) do
    before_s = rules["window_before_minutes"] * 60
    after_s = rules["window_after_minutes"] * 60

    Enum.any?(facts.bookings, fn booking ->
      same_branch? = is_nil(booking.location_id) or booking.location_id == facts.location_id
      opens = DateTime.add(booking.starts_at, -before_s, :second)
      closes = DateTime.add(booking.starts_at, after_s, :second)

      same_branch? and DateTime.compare(now, opens) != :lt and
        DateTime.compare(now, closes) != :gt
    end)
  end

  @doc "Whether `local` falls in one of the periods; no periods means always open."
  def within_hours?([], _local), do: true

  def within_hours?(hours, %NaiveDateTime{} = local) when is_list(hours) do
    day = local |> NaiveDateTime.to_date() |> Date.day_of_week()
    minute = local.hour * 60 + local.minute

    Enum.any?(hours, fn %{"days" => days, "from" => from, "to" => to} ->
      day in days and minute >= minutes(from) and minute < minutes(to)
    end)
  end

  @doc """
  Validates the owner's rules for a door: `{:ok, rules}` with defaults
  filled, or `{:error, :invalid_door_rules}`.
  """
  def normalize(params) when is_map(params) do
    rules =
      params
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.take(Map.keys(@defaults))
      |> then(&Map.merge(@defaults, &1))

    with true <- rules["who"] in @whos,
         true <- is_boolean(rules["staff_always"]),
         true <- minutes_in?(rules["window_before_minutes"], 0..180),
         true <- minutes_in?(rules["window_after_minutes"], 0..180),
         true <- minutes_in?(rules["unlock_seconds"], 1..30),
         {:ok, hours} <- normalize_hours(rules["hours"]) do
      {:ok, Map.put(rules, "hours", hours)}
    else
      _invalid -> {:error, :invalid_door_rules}
    end
  end

  def normalize(_params), do: {:error, :invalid_door_rules}

  defp normalize_hours(hours) when is_list(hours) and length(hours) <= 14 do
    hours
    |> Enum.reduce_while({:ok, []}, fn period, {:ok, acc} ->
      case normalize_period(period) do
        {:ok, period} -> {:cont, {:ok, [period | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, periods} -> {:ok, Enum.reverse(periods)}
      :error -> :error
    end
  end

  defp normalize_hours(_hours), do: :error

  defp normalize_period(%{} = period) do
    period = Map.new(period, fn {key, value} -> {to_string(key), value} end)

    with days when is_list(days) and days != [] <- period["days"],
         true <- Enum.all?(days, &(&1 in 1..7)),
         from when is_binary(from) <- period["from"],
         to when is_binary(to) <- period["to"],
         f when is_integer(f) <- minutes(from),
         t when is_integer(t) and t > f <- minutes(to) do
      {:ok, %{"days" => days |> Enum.uniq() |> Enum.sort(), "from" => from, "to" => to}}
    else
      _invalid -> :error
    end
  end

  defp normalize_period(_period), do: :error

  defp minutes_in?(value, range) when is_integer(value), do: value in range
  defp minutes_in?(_value, _range), do: false

  # "06:30" -> 390; "24:00" closes a day.
  defp minutes(<<h::binary-size(2), ":", m::binary-size(2)>>) do
    with {hour, ""} <- Integer.parse(h),
         {minute, ""} <- Integer.parse(m),
         true <- hour in 0..24 and minute in 0..59 and hour * 60 + minute <= 1_440 do
      hour * 60 + minute
    else
      _invalid -> nil
    end
  end

  defp minutes(_value), do: nil
end
