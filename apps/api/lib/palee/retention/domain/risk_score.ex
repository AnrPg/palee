defmodule Palee.Retention.Domain.RiskScore do
  @moduledoc """
  ADR-347: how likely a box member is to leave, as a score from 0 to 100
  that staff can read line by line. Pure. No model, no hidden weights:
  every point comes from one named reason with the facts it read, so the
  list can say «2 φορές τον μήνα αντί για 3 την εβδομάδα» instead of a
  number.

  | Reason | Points | When |
  |---|---|---|
  | `attendance_drop` | up to 40 | the last 4 weeks are under half the usual weekly visits of the 8 weeks before |
  | `absent` | 25 / 35 | no class for 14 / 21 days or more |
  | `no_first_visit` | 30 | a box member for 14 days or more who never came |
  | `no_upcoming_bookings` | 10 | someone who usually books has nothing booked for the next 14 days |
  | `package_ending` | 20 | the subscription package ends within 14 days and does not renew by itself |
  | `payment_overdue` | 15 | an invoice is overdue |
  | `many_cancellations` | 10 | 3 or more cancelled bookings in 4 weeks |
  | `new_member_slow_start` | 10 | in the first 60 days, fewer than 4 classes in the last 4 weeks |

  Levels: `high` from 60, `medium` from 30, else `low`. The suggested
  action follows the reason with the most points.
  """

  @high 60
  @medium 30

  @type signals :: %{
          optional(:visits_recent) => non_neg_integer(),
          optional(:visits_baseline) => non_neg_integer(),
          optional(:days_since_last_visit) => non_neg_integer() | nil,
          optional(:upcoming_bookings) => non_neg_integer(),
          optional(:cancellations_recent) => non_neg_integer(),
          optional(:package_ends_in_days) => integer() | nil,
          optional(:package_renews) => boolean(),
          optional(:overdue_invoices) => non_neg_integer(),
          optional(:member_for_days) => non_neg_integer() | nil
        }

  @type reason :: %{code: String.t(), points: pos_integer(), facts: map()}

  def levels, do: ~w(low medium high)

  def reason_codes,
    do: ~w(attendance_drop absent no_first_visit no_upcoming_bookings package_ending
           payment_overdue many_cancellations new_member_slow_start)

  def actions, do: ~w(personal_message renewal_offer payment_follow_up check_in_call none)

  @doc "`%{score, level, reasons, suggested_action}` from a member's signals."
  @spec score(signals()) :: %{
          score: 0..100,
          level: String.t(),
          reasons: [reason()],
          suggested_action: String.t()
        }
  def score(signals) do
    reasons =
      [
        attendance_drop(signals),
        absent(signals),
        no_first_visit(signals),
        no_upcoming_bookings(signals),
        package_ending(signals),
        payment_overdue(signals),
        many_cancellations(signals),
        slow_start(signals)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.points, :desc)

    score = reasons |> Enum.map(& &1.points) |> Enum.sum() |> min(100)

    %{
      score: score,
      level: level(score),
      reasons: reasons,
      suggested_action: action(reasons)
    }
  end

  def level(score) when score >= @high, do: "high"
  def level(score) when score >= @medium, do: "medium"
  def level(_score), do: "low"

  # Weekly visits: the last 4 weeks against the 8 weeks before them.
  defp attendance_drop(%{visits_recent: recent, visits_baseline: baseline})
       when is_integer(recent) and is_integer(baseline) and baseline >= 8 do
    usual = baseline / 8
    now = recent / 4

    if now < usual / 2 do
      %{
        code: "attendance_drop",
        points: round(40 * (1 - now / usual)),
        facts: %{"per_week_now" => Float.round(now, 1), "per_week_usual" => Float.round(usual, 1)}
      }
    end
  end

  defp attendance_drop(_signals), do: nil

  defp absent(%{days_since_last_visit: days}) when is_integer(days) and days >= 21,
    do: %{code: "absent", points: 35, facts: %{"days" => days}}

  defp absent(%{days_since_last_visit: days}) when is_integer(days) and days >= 14,
    do: %{code: "absent", points: 25, facts: %{"days" => days}}

  defp absent(_signals), do: nil

  defp no_first_visit(%{days_since_last_visit: nil, member_for_days: days})
       when is_integer(days) and days >= 14,
       do: %{code: "no_first_visit", points: 30, facts: %{"member_for_days" => days}}

  defp no_first_visit(_signals), do: nil

  defp no_upcoming_bookings(%{upcoming_bookings: 0, visits_baseline: baseline})
       when is_integer(baseline) and baseline >= 4,
       do: %{code: "no_upcoming_bookings", points: 10, facts: %{"days_ahead" => 14}}

  defp no_upcoming_bookings(_signals), do: nil

  defp package_ending(%{package_ends_in_days: days, package_renews: false})
       when is_integer(days) and days >= 0 and days <= 14,
       do: %{code: "package_ending", points: 20, facts: %{"days" => days}}

  defp package_ending(_signals), do: nil

  defp payment_overdue(%{overdue_invoices: count}) when is_integer(count) and count > 0,
    do: %{code: "payment_overdue", points: 15, facts: %{"invoices" => count}}

  defp payment_overdue(_signals), do: nil

  defp many_cancellations(%{cancellations_recent: count}) when is_integer(count) and count >= 3,
    do: %{code: "many_cancellations", points: 10, facts: %{"cancellations" => count}}

  defp many_cancellations(_signals), do: nil

  defp slow_start(%{member_for_days: days, visits_recent: recent} = signals)
       when is_integer(days) and days < 60 and is_integer(recent) and recent < 4 do
    # Someone who never came is `no_first_visit` already.
    if is_nil(Map.get(signals, :days_since_last_visit)) and days >= 14,
      do: nil,
      else: %{
        code: "new_member_slow_start",
        points: 10,
        facts: %{"member_for_days" => days, "visits" => recent}
      }
  end

  defp slow_start(_signals), do: nil

  defp action([]), do: "none"

  defp action([%{code: code} | _rest]) do
    case code do
      "payment_overdue" -> "payment_follow_up"
      "package_ending" -> "renewal_offer"
      "new_member_slow_start" -> "check_in_call"
      "no_first_visit" -> "check_in_call"
      _other -> "personal_message"
    end
  end
end
