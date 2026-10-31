defmodule Palee.Infrastructure.DataQuestions.SqlBoxDataReader do
  @moduledoc """
  `BoxDataReader` over the box's own tables (ADR-361): fixed, parameterised
  read-only SQL per catalogue query, run in the tenant session (row-level
  security) and with an explicit `organization_id` predicate besides.
  Nothing here is built from model text: the query name picks a statement
  and the arguments are already validated integers and dates.
  """

  @behaviour Palee.DataQuestions.Ports.BoxDataReader

  alias Palee.Repo

  @row_limit 100
  @active_statuses ~w(active expiring comped)

  @impl true
  def run(%{organization_id: organization_id}, query, params, zone) do
    org = Ecto.UUID.dump!(organization_id)
    {:ok, read(query, org, params, zone)}
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, {:query_failed, Exception.message(error)}}
  end

  defp read("members_absent", org, %{"days" => days, "today" => today}, zone) do
    since = Date.add(today, -days + 1)

    rows =
      select(
        """
        WITH active AS (
          SELECT DISTINCT m.user_id FROM memberships m
          WHERE m.organization_id = $1 AND m.status = ANY($4) AND m.left_at IS NULL
            AND m.user_type_snapshot IN ('member', 'athlete')
        ), visits AS (
          SELECT r.user_id, max((c.scheduled_at AT TIME ZONE 'UTC' AT TIME ZONE $2)::date) AS last_on
          FROM class_attendance_records r
          JOIN scheduled_classes c ON c.id = r.scheduled_class_id AND c.organization_id = $1
          WHERE r.organization_id = $1 AND r.status = 'attended'
          GROUP BY r.user_id
          UNION ALL
          SELECT f.user_id, max(f.checked_in_on) FROM facility_check_ins f
          WHERE f.organization_id = $1 AND f.user_id IS NOT NULL
          GROUP BY f.user_id
        ), last_visit AS (
          SELECT user_id, max(last_on) AS last_on FROM visits GROUP BY user_id
        )
        SELECT a.user_id, COALESCE(u.display_nickname, u.nickname) AS name, lv.last_on,
               count(*) OVER () AS total
        FROM active a
        JOIN users u ON u.id = a.user_id
        LEFT JOIN last_visit lv ON lv.user_id = a.user_id
        WHERE lv.last_on IS NULL OR lv.last_on < $3
        ORDER BY lv.last_on ASC NULLS FIRST, name
        LIMIT #{@row_limit}
        """,
        [org, zone, since, @active_statuses]
      )

    %{
      summary: %{
        "members" => total(rows),
        "days" => days,
        "never_came" => Enum.count(rows, &is_nil(Enum.at(&1, 2)))
      },
      rows:
        Enum.map(rows, fn [user_id, name, last_on, _total] ->
          %{
            "user_id" => load_uuid(user_id),
            "name" => name,
            "last_visit_on" => last_on,
            "days_since_last_visit" => if(last_on, do: Date.diff(today, last_on))
          }
        end)
    }
  end

  defp read("member_counts", org, %{"from" => from, "to" => to}, zone) do
    [[active, joined, left]] =
      select(
        """
        SELECT
          (SELECT count(DISTINCT user_id) FROM memberships
             WHERE organization_id = $1 AND status = ANY($5) AND left_at IS NULL
               AND user_type_snapshot IN ('member', 'athlete')),
          (SELECT count(DISTINCT user_id) FROM memberships
             WHERE organization_id = $1 AND starts_on BETWEEN $2 AND $3
               AND user_type_snapshot IN ('member', 'athlete')),
          (SELECT count(DISTINCT user_id) FROM memberships
             WHERE organization_id = $1 AND left_at IS NOT NULL
               AND (left_at AT TIME ZONE 'UTC' AT TIME ZONE $4)::date BETWEEN $2 AND $3)
        """,
        [org, from, to, zone, @active_statuses]
      )

    %{summary: %{"active_members" => active, "joined" => joined, "left" => left}, rows: []}
  end

  defp read("expiring_subscriptions", org, %{"days" => days, "today" => today}, _zone) do
    rows =
      select(
        """
        SELECT m.user_id, COALESCE(u.display_nickname, u.nickname) AS name,
               COALESCE(p.name, s.package_code_snapshot) AS package, s.ends_on,
               count(*) OVER () AS total
        FROM membership_package_subscriptions s
        JOIN memberships m ON m.id = s.membership_id AND m.organization_id = $1
        JOIN users u ON u.id = m.user_id
        LEFT JOIN membership_packages p ON p.id = s.membership_package_id
        WHERE s.organization_id = $1 AND s.status = 'active'
          AND s.ends_on BETWEEN $2 AND $3 AND NOT COALESCE(s.auto_renew, false)
        ORDER BY s.ends_on, name
        LIMIT #{@row_limit}
        """,
        [org, today, Date.add(today, days)]
      )

    %{
      summary: %{"subscriptions" => total(rows), "days" => days},
      rows:
        Enum.map(rows, fn [user_id, name, package, ends_on, _total] ->
          %{
            "user_id" => load_uuid(user_id),
            "name" => name,
            "package" => package,
            "ends_on" => ends_on,
            "days_left" => Date.diff(ends_on, today)
          }
        end)
    }
  end

  defp read("revenue_by_package", org, %{"from" => from, "to" => to}, _zone) do
    rows =
      select(
        """
        SELECT COALESCE(p.name, s.package_code_snapshot) AS package, mp.currency,
               count(*), sum(mp.amount_cents)::bigint
        FROM membership_payments mp
        LEFT JOIN membership_package_subscriptions s
          ON s.id = mp.membership_package_subscription_id AND s.organization_id = $1
        LEFT JOIN membership_packages p ON p.id = s.membership_package_id
        WHERE mp.organization_id = $1 AND mp.payment_status = 'paid' AND mp.deleted_at IS NULL
          AND COALESCE(mp.revenue_stream, 'membership') IN ('membership', 'package')
          AND mp.paid_on BETWEEN $2 AND $3
        GROUP BY 1, 2
        ORDER BY 4 DESC
        LIMIT #{@row_limit}
        """,
        [org, from, to]
      )

    rows =
      Enum.map(rows, fn [package, currency, count, cents] ->
        %{
          "package" => package,
          "currency" => currency,
          "payments" => count,
          "amount_cents" => cents
        }
      end)

    %{summary: money_summary(rows), rows: rows}
  end

  defp read("revenue_by_month", org, %{"months" => months, "today" => today}, _zone) do
    first = today |> Date.beginning_of_month() |> Date.shift(month: -(months - 1))

    rows =
      select(
        """
        SELECT to_char(mp.paid_on, 'YYYY-MM') AS month, mp.currency, count(*),
               sum(mp.amount_cents)::bigint
        FROM membership_payments mp
        WHERE mp.organization_id = $1 AND mp.payment_status = 'paid' AND mp.deleted_at IS NULL
          AND COALESCE(mp.revenue_stream, 'membership') IN ('membership', 'package')
          AND mp.paid_on BETWEEN $2 AND $3
        GROUP BY 1, 2
        ORDER BY 1, 2
        """,
        [org, first, today]
      )

    rows =
      Enum.map(rows, fn [month, currency, count, cents] ->
        %{"month" => month, "currency" => currency, "payments" => count, "amount_cents" => cents}
      end)

    %{summary: money_summary(rows), rows: rows}
  end

  defp read("attendance_by_class_type", org, %{"from" => from, "to" => to}, zone) do
    rows =
      select(
        """
        WITH classes AS (
          SELECT c.id, COALESCE(c.capacity, 0) AS capacity, COALESCE(t.name, c.name) AS class_type
          FROM scheduled_classes c
          LEFT JOIN class_types t ON t.id = c.class_type_id
          WHERE c.organization_id = $1 AND c.cancelled_at IS NULL
            AND (c.scheduled_at AT TIME ZONE 'UTC' AT TIME ZONE $4)::date BETWEEN $2 AND $3
        ), attended AS (
          SELECT r.scheduled_class_id, count(*) AS n
          FROM class_attendance_records r
          WHERE r.organization_id = $1 AND r.status = 'attended'
            AND r.scheduled_class_id IN (SELECT id FROM classes)
          GROUP BY r.scheduled_class_id
        )
        SELECT classes.class_type, count(*), COALESCE(sum(attended.n), 0)::bigint,
               sum(classes.capacity)::bigint
        FROM classes LEFT JOIN attended ON attended.scheduled_class_id = classes.id
        GROUP BY classes.class_type
        ORDER BY 3 DESC, 1
        LIMIT #{@row_limit}
        """,
        [org, from, to, zone]
      )

    rows =
      Enum.map(rows, fn [class_type, classes, attendances, capacity] ->
        %{
          "class_type" => class_type,
          "classes" => classes,
          "attendances" => attendances,
          "average_per_class" => Float.round(attendances / max(classes, 1), 1),
          "fill_percent" => if(capacity > 0, do: round(attendances * 100 / capacity))
        }
      end)

    %{
      summary: %{
        "classes" => Enum.sum(Enum.map(rows, & &1["classes"])),
        "attendances" => Enum.sum(Enum.map(rows, & &1["attendances"]))
      },
      rows: rows
    }
  end

  defp money_summary(rows) do
    payments = Enum.sum(Enum.map(rows, & &1["payments"]))

    case rows |> Enum.map(& &1["currency"]) |> Enum.uniq() do
      [currency] ->
        %{
          "payments" => payments,
          "currency" => currency,
          "amount_cents" => Enum.sum(Enum.map(rows, & &1["amount_cents"]))
        }

      _none_or_several ->
        %{"payments" => payments}
    end
  end

  defp select(sql, params), do: Repo.query!(sql, params).rows

  defp total([]), do: 0
  defp total([first | _rest]), do: List.last(first)

  defp load_uuid(nil), do: nil
  defp load_uuid(binary), do: Ecto.UUID.load!(binary)
end
