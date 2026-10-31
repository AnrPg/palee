defmodule Palee.Application.CoachPay.CoachPayService do
  @moduledoc """
  CP-A6 (ADR-341) use cases for «Αμοιβές coaches»: staff set each coach's
  pay rules, open a pay period, calculate it from the classes, sessions and
  sales of the period, adjust, approve and export it for the accountant;
  a coach reads their own approved statements.

  Names of coaches and members come from Identity; amounts stay in the
  period's currency (the business's). Nothing here writes Finance or
  issues a fiscal document.
  """

  alias Palee.{CoachPay, Fiscal, Identity, Organizations}

  # ── Rules ───────────────────────────────────────────────────────────────

  def rules(context, params) do
    rules = CoachPay.list_rules(context, Map.take(params, [:coach_user_id, :include_archived]))
    %{rules: with_coach_names(rules)}
  end

  def create_rule(context, params) do
    params = Map.put_new(stringify(params), "currency", currency(context))

    with :ok <- coach_of_box(context, params["coach_user_id"]),
         {:ok, rule} <- CoachPay.create_rule(context, params, Map.get(context, :user_id)) do
      {:ok, rule |> List.wrap() |> with_coach_names() |> hd()}
    end
  end

  def update_rule(context, id, params) do
    params = stringify(params)

    with :ok <- maybe_coach(context, params["coach_user_id"]),
         {:ok, rule} <- CoachPay.update_rule(context, id, params) do
      {:ok, rule |> List.wrap() |> with_coach_names() |> hd()}
    end
  end

  def archive_rule(context, id) do
    now = now()
    CoachPay.archive_rule(context, id, Organizations.local_today(context.organization_id, now), now)
  end

  # ── Periods ─────────────────────────────────────────────────────────────

  def periods(context, params),
    do: %{periods: CoachPay.list_periods(context, Map.take(params, [:status]))}

  def create_period(context, params) do
    with {:ok, starts_on} <- date(params[:starts_on], "starts_on"),
         {:ok, ends_on} <- date(params[:ends_on], "ends_on") do
      CoachPay.create_period(
        context,
        starts_on,
        ends_on,
        currency(context),
        Map.get(context, :user_id)
      )
    end
  end

  def period(context, id), do: context |> CoachPay.get_period(id) |> named()

  def calculate(context, id), do: context |> CoachPay.calculate(id, now()) |> named()

  def add_adjustment(context, id, params) do
    with :ok <- coach_of_box(context, params[:coach_user_id]) do
      context
      |> CoachPay.add_adjustment(
        id,
        params[:coach_user_id],
        stringify(params),
        Map.get(context, :user_id)
      )
      |> named()
    end
  end

  def delete_adjustment(context, id, line_id),
    do: context |> CoachPay.delete_adjustment(id, line_id) |> named()

  def approve(context, id),
    do: context |> CoachPay.approve(id, Map.get(context, :user_id), now()) |> named()

  def reopen(context, id, params), do: context |> CoachPay.reopen(id, params[:reason]) |> named()

  @doc "CSV for the accountant (`{:ok, filename, csv}`)."
  def export(context, id) do
    with {:ok, period} <- CoachPay.get_period(context, id),
         names = names(Enum.map(period.statements, & &1.coach_user_id)),
         {:ok, csv} <- CoachPay.export(context, id, names, now()) do
      {:ok, "coach-pay-#{period.starts_on}-#{period.ends_on}.csv", csv}
    end
  end

  # ── The coach ───────────────────────────────────────────────────────────

  def my_statements(context),
    do: %{statements: CoachPay.coach_statements(context, context.user_id)}

  # ── helpers ─────────────────────────────────────────────────────────────

  defp named({:ok, %{statements: statements} = period}) do
    names = names(Enum.map(statements, & &1.coach_user_id))

    {:ok,
     %{
       period
       | statements: Enum.map(statements, &Map.put(&1, :coach_name, Map.get(names, &1.coach_user_id)))
     }}
  end

  defp named(other), do: other

  defp with_coach_names(rules) do
    names = names(Enum.map(rules, & &1.coach_user_id))
    Enum.map(rules, &Map.put(&1, :coach_name, Map.get(names, &1.coach_user_id)))
  end

  defp names(ids) do
    case Enum.uniq(ids) do
      [] -> %{}
      ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})
    end
  end

  # Only the box's own staff can be paid as coaches.
  defp coach_of_box(context, user_id) when is_binary(user_id) do
    roles =
      context
      |> Organizations.member_roles_by_user()
      |> Map.get(user_id)

    if roles && Enum.any?(roles.roles, &(&1 in [:owner, :admin, :coach, "owner", "admin", "coach"])),
      do: :ok,
      else: {:error, {:invalid_fields, %{"coach_user_id" => "not_a_coach"}}}
  end

  defp coach_of_box(_context, _user_id),
    do: {:error, {:invalid_fields, %{"coach_user_id" => "required"}}}

  defp maybe_coach(_context, nil), do: :ok
  defp maybe_coach(context, user_id), do: coach_of_box(context, user_id)

  defp currency(context) do
    case Fiscal.identity_status(context) do
      %{profile: %{currency: currency}} when is_binary(currency) -> currency
      _none -> "EUR"
    end
  end

  defp date(%Date{} = date, _field), do: {:ok, date}

  defp date(value, field) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _error -> {:error, {:invalid_fields, %{field => "invalid"}}}
    end
  end

  defp date(_value, field), do: {:error, {:invalid_fields, %{field => "required"}}}

  defp stringify(params) when is_map(params),
    do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp now, do: CoachPay.clock().now()
end
