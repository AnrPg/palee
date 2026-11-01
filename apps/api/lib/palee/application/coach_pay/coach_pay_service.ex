defmodule Palee.Application.CoachPay.CoachPayService do
  @moduledoc """
  CP-A6 (ADR-341) use cases for «Αμοιβές coaches»: staff set each coach's
  pay rules, open a pay period, calculate it from the classes, sessions and
  sales of the period, adjust, approve and export it for the accountant;
  a coach reads their own approved statements.

  ADR-382 adds the catalogue of overtime and allowances (Settings), lines
  added by hand (payments by hand, allowances, reimbursements), each line's
  gross or net basis, the internal pay statement as PDF («Εκκαθαριστικό»),
  a person's statements for their staff profile and Finance's summary.

  Names of coaches and members come from Identity; amounts stay in the
  period's currency (the business's). Nothing here writes Finance or
  issues a fiscal document.
  """

  alias Palee.{CoachPay, Fiscal, Identity, Localization, Organizations}
  alias Palee.CoachPay.Domain.Payslip
  alias Palee.Pdf.Fonts

  # Who may be paid through coach pay: the box's staff (ADR-382 widens
  # ADR-341's owner/admin/coach to every staff role, for allowances and
  # fixed pay of the desk and the accountant).
  @payable_roles ~w(owner admin coach front_desk accountant janitor)

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

    CoachPay.archive_rule(
      context,
      id,
      Organizations.local_today(context.organization_id, now),
      now
    )
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

  @doc "ADR-382: an allowance from the catalogue for one person of a draft period."
  def add_pay_item_line(context, id, params) do
    params = stringify(params)
    user_id = params["user_id"]

    with :ok <- coach_of_box(context, user_id) do
      context
      |> CoachPay.add_pay_item_line(
        id,
        user_id,
        person_roles(context, user_id),
        params,
        Map.get(context, :user_id)
      )
      |> named()
    end
  end

  @doc "ADR-382: a line's basis (`gross` or `net`) in a draft period."
  def set_line_basis(context, id, line_id, params),
    do:
      context
      |> CoachPay.set_line_basis(id, line_id, params[:amount_basis] || params["amount_basis"])
      |> named()

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

  @doc "My approved statements with their totals (gross and net apart)."
  def my_statements(context),
    do: context |> CoachPay.coach_statements(context.user_id) |> with_totals()

  @doc """
  ADR-382: a staff member's statements for their profile (Finance staff),
  every period status, with totals per currency (gross and net apart).
  """
  def person_statements(context, user_id) do
    context
    |> CoachPay.coach_statements(user_id, ["draft", "approved", "exported"])
    |> with_totals()
  end

  defp with_totals(statements) do
    totals =
      statements
      |> Enum.group_by(& &1.period.currency)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {currency, statements} ->
        %{
          currency: currency,
          statement_count: length(statements),
          gross_cents: statements |> Enum.map(& &1.gross_cents) |> Enum.sum(),
          net_cents: statements |> Enum.map(& &1.net_cents) |> Enum.sum()
        }
      end)

    %{statements: statements, totals: totals}
  end

  @doc """
  ADR-382: Finance's summary, per period and per person (gross and net
  apart), periods starting between `from` and `to` when given.
  """
  def summary(context, params) do
    with {:ok, from} <- optional_date(params[:from], "from"),
         {:ok, to} <- optional_date(params[:to], "to") do
      periods = CoachPay.summary(context, %{from: from, to: to})

      names =
        names(for period <- periods, statement <- period.statements, do: statement.coach_user_id)

      {:ok,
       %{
         periods:
           Enum.map(periods, fn period ->
             %{
               period
               | statements:
                   Enum.map(
                     period.statements,
                     &Map.put(&1, :coach_name, Map.get(names, &1.coach_user_id))
                   )
             }
           end)
       }}
    end
  end

  defp optional_date(nil, _field), do: {:ok, nil}
  defp optional_date(value, field), do: date(value, field)

  # ── Pay statement PDF (ADR-382) ─────────────────────────────────────────

  @doc """
  One person's statement of an approved or exported period as PDF
  (`{:ok, %{content, content_type, filename}}`), in `language` or the
  business's document language (Greek when none). Staff with coach pay
  rights ask for anyone (`my_payslip/3` for one's own).
  """
  def payslip(context, period_id, user_id, language \\ nil) do
    with {:ok, language} <- payslip_language(context, language),
         {:ok, %{period: period, statement: statement}} <-
           CoachPay.approved_statement(context, period_id, user_id) do
      labels = payslip_labels(language)
      view = payslip_view(context, period, statement, language)

      {:ok,
       %{
         content: Payslip.render(view, labels, Fonts.sans(), created_at: period.approved_at),
         content_type: "application/pdf",
         filename: "pay-statement-#{period.starts_on}-#{period.ends_on}.pdf"
       }}
    end
  end

  @doc "My own pay statement PDF of an approved period."
  def my_payslip(context, period_id, language \\ nil),
    do: payslip(context, period_id, context.user_id, language)

  defp payslip_language(context, nil) do
    case Fiscal.identity_status(context) do
      %{identity: %{document_language: language}} when is_binary(language) ->
        payslip_language(context, language)

      _none ->
        {:ok, "el"}
    end
  end

  defp payslip_language(_context, language) do
    language = if language == "pt_PT", do: "pt-PT", else: language

    if language in Payslip.languages(),
      do: {:ok, language},
      else: {:error, :unsupported_language}
  end

  defp payslip_labels(language) do
    Map.new(Payslip.label_messages(), fn {key, message} ->
      {key, Localization.translate(language, message, %{}, "coach_pay")}
    end)
  end

  defp payslip_view(context, period, statement, language) do
    {calculated, manual} = Enum.split_with(statement.lines, &(&1.source_type != "manual"))
    groups = CoachPay.with_groups(%{statement | lines: calculated}).groups

    %{
      business: business(context),
      person: Map.get(names([statement.coach_user_id]), statement.coach_user_id) || "",
      period: Map.take(period, [:starts_on, :ends_on, :approved_at]),
      currency: period.currency,
      gross_cents: statement.gross_cents,
      net_cents: statement.net_cents,
      groups: groups,
      manual: manual,
      language: language
    }
  end

  defp business(context) do
    identity =
      case Fiscal.identity_status(context) do
        %{identity: %{} = identity} -> identity
        _none -> %{}
      end

    organization_name =
      case Map.get(context, :organization) do
        %{name: name} when is_binary(name) -> name
        _none -> ""
      end

    address =
      [
        Enum.join(
          Enum.reject(
            [Map.get(identity, :street), Map.get(identity, :building_number)],
            &blank?/1
          ),
          " "
        ),
        Enum.join(
          Enum.reject([Map.get(identity, :postal_code), Map.get(identity, :city)], &blank?/1),
          " "
        )
      ]
      |> Enum.reject(&blank?/1)

    %{
      name:
        first_present([
          Map.get(identity, :trade_name),
          Map.get(identity, :legal_name),
          organization_name
        ]),
      lines:
        Enum.reject(
          [Map.get(identity, :legal_name)],
          &(blank?(&1) or &1 == Map.get(identity, :trade_name))
        ) ++
          address,
      ids:
        [{"TIN", Map.get(identity, :tax_id)}, {"VAT", Map.get(identity, :vat_number)}]
        |> Enum.reject(fn {_term, value} -> blank?(value) end)
    }
  end

  defp first_present(values), do: Enum.find(values, "", &(not blank?(&1)))
  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""

  # ── Pay items (ADR-382) ─────────────────────────────────────────────────

  def items(context, params),
    do: %{items: CoachPay.list_items(context, Map.take(params, [:kind, :include_archived]))}

  def create_item(context, params) do
    params = Map.put_new(stringify(params), "currency", currency(context))
    CoachPay.create_item(context, params, Map.get(context, :user_id))
  end

  def update_item(context, id, params), do: CoachPay.update_item(context, id, stringify(params))

  def archive_item(context, id), do: CoachPay.archive_item(context, id, now())

  # ── helpers ─────────────────────────────────────────────────────────────

  defp named({:ok, %{statements: statements} = period}) do
    names = names(Enum.map(statements, & &1.coach_user_id))

    {:ok,
     %{
       period
       | statements:
           Enum.map(statements, &Map.put(&1, :coach_name, Map.get(names, &1.coach_user_id)))
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

  # Only the box's own staff can be paid.
  defp coach_of_box(context, user_id) when is_binary(user_id) do
    roles =
      context
      |> Organizations.member_roles_by_user()
      |> Map.get(user_id)

    if roles && Enum.any?(roles.roles, &(to_string(&1) in @payable_roles)),
      do: :ok,
      else: {:error, {:invalid_fields, %{"coach_user_id" => "not_a_coach"}}}
  end

  defp coach_of_box(_context, _user_id),
    do: {:error, {:invalid_fields, %{"coach_user_id" => "required"}}}

  defp person_roles(context, user_id) do
    case context |> Organizations.member_roles_by_user() |> Map.get(user_id) do
      nil -> []
      member -> CoachPay.person_roles(member.roles, Map.get(member, :coach_scope))
    end
  end

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
