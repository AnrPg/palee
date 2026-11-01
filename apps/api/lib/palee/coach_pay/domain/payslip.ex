defmodule Palee.CoachPay.Domain.Payslip do
  @moduledoc """
  ADR-382: one person's statement of an approved period as an A4 PDF
  («Εκκαθαριστικό»), drawn with `Palee.Pdf` (ADR-245) and embedded
  Liberation Sans, pure.

  It says at the top and the foot that it is an internal record of the
  business («Εσωτερική κατάσταση αμοιβής»), not an official payroll
  document. Content: the business (name, address, tax ids), the person,
  the period, one row per group of the statement with its terms and
  quantity × rate, then each line added by hand (payments by hand,
  allowances, adjustments) with its note, and the total in the period's
  currency.

  `view` (built by the application service):

      %{business: %{name, lines: [String.t()], ids: [{term, value}]},
        person: String.t(), period: %{starts_on, ends_on, approved_at},
        currency: String.t(), total_cents: integer(),
        groups: [StatementGroups group of the calculated lines],
        manual: [line added by hand], language: String.t()}

  `labels` maps the keys of `label_messages/0` to the language's words.
  """

  alias Palee.Pdf

  @mm 72 / 25.4
  @page_height 297
  @left 18
  @right 192
  @bottom 22

  @label_messages [
    title: "Pay statement",
    internal: "Internal pay statement",
    disclaimer:
      "An internal record of the business for paying its staff, not an official payroll document.",
    business: "Business",
    paid_to: "Paid to",
    period: "Period",
    approved_on: "Approved on",
    item: "Item",
    terms: "Terms",
    quantity_rate: "Quantity × rate",
    amount: "Amount",
    added_by_hand: "Added by hand",
    note: "Note",
    total: "Total",
    page: "Page",
    fixed: "Fixed pay",
    per_class: "Per class",
    per_attendee: "Per attendee",
    per_session: "Per personal session",
    percent_of_sales: "Percent of sales",
    overtime: "Overtime",
    allowance: "Allowance",
    ad_hoc: "Ad hoc payment",
    adjustment: "Adjustment",
    monthly: "per month",
    weekly: "per week",
    daily: "per day",
    personal_training: "personal training packages they coach",
    sold_by: "sales they recorded",
    own_clients: "subscriptions of their own clients",
    box_all: "all subscriptions of the box",
    per_hour: "per hour",
    per_period: "per period",
    per_occurrence: "per occurrence",
    weekly_threshold: "above %{threshold} a week"
  ]

  @doc "`[{key, English message}]`: the gettext msgids (domain `coach_pay`)."
  def label_messages, do: @label_messages

  @doc "Languages the PDF is drawn in (left to right, Latin, Greek and Cyrillic)."
  def languages, do: ~w(el en de fr it nl es pt-PT ru bg)

  @doc "The PDF bytes."
  def render(view, labels, fonts, opts \\ []) do
    view
    |> layout(labels, fonts)
    |> Pdf.render(
      title: "#{labels.title} #{view.person} #{view.period.starts_on}",
      author: view.business.name,
      created_at: Keyword.get(opts, :created_at)
    )
  end

  @doc "The texts a render draws, in order (for checks without parsing the PDF)."
  def texts(view, labels, fonts), do: view |> layout(labels, fonts) |> Pdf.texts()

  defp layout(view, labels, fonts) do
    %{pdf: Pdf.new(fonts), y: 18, page: 1, view: view, l: labels}
    |> header()
    |> parties()
    |> groups()
    |> manual()
    |> total()
    |> footer()
    |> Map.fetch!(:pdf)
  end

  # ── Sections ──────────────────────────────────────────────────────────────

  defp header(%{view: view, l: l} = s) do
    s
    |> text(@left, s.y + 6, l.title, font: :bold, size: 16)
    |> text(@right, s.y + 3, l.period, size: 8.5, align: :right, color: {0.3, 0.3, 0.3})
    |> text(
      @right,
      s.y + 7.4,
      "#{date(view.period.starts_on)} – #{date(view.period.ends_on)}",
      font: :bold,
      size: 8.5,
      align: :right
    )
    |> approved(view.period[:approved_at])
    |> Map.put(:y, s.y + 12)
    |> banner()
  end

  defp approved(s, nil), do: s

  defp approved(%{l: l} = s, %DateTime{} = at) do
    s
    |> text(150, s.y + 11.8, l.approved_on, size: 8.5, align: :right, color: {0.3, 0.3, 0.3})
    |> text(@right, s.y + 11.8, date(DateTime.to_date(at)), size: 8.5, align: :right)
  end

  # The notice that this is not a payroll document, boxed under the title.
  defp banner(%{l: l} = s) do
    lines = Pdf.wrap(s.pdf, l.disclaimer, mm(@right - @left - 6), size: 8.5)
    height = 6 + length(lines) * 4

    s = %{
      s
      | pdf:
          Pdf.rect(
            s.pdf,
            mm(@left),
            mm(@page_height - s.y - height - 2),
            mm(@right - @left),
            mm(height + 2),
            fill: true,
            color: {0.94, 0.94, 0.94}
          )
    }

    s = text(s, @left + 3, s.y + 4.5, l.internal, font: :bold, size: 9.5)

    s =
      lines
      |> Enum.with_index()
      |> Enum.reduce(s, fn {line, index}, s ->
        text(s, @left + 3, s.y + 9 + index * 4, line, size: 8.5)
      end)

    %{s | y: s.y + height + 8}
  end

  defp parties(%{view: view, l: l} = s) do
    top = s.y
    business = view.business

    rows =
      business.lines ++ Enum.map(business.ids, fn {term, value} -> "#{term}: #{value}" end)

    s = text(s, @left, top, String.upcase(l.business), size: 7.5, color: {0.3, 0.3, 0.3})
    s = text(s, @left, top + 4.5, business.name, font: :bold, size: 10)

    {s, business_y} =
      rows
      |> Enum.flat_map(&Pdf.wrap(s.pdf, &1, mm(78), size: 9))
      |> Enum.with_index()
      |> Enum.reduce({s, top + 4.5}, fn {row, index}, {s, _y} ->
        y = top + 9 + index * 4
        {text(s, @left, y, row, size: 9), y}
      end)

    s =
      s
      |> text(110, top, String.upcase(l.paid_to), size: 7.5, color: {0.3, 0.3, 0.3})
      |> text(110, top + 4.5, view.person, font: :bold, size: 10)

    s = %{s | y: max(business_y, top + 4.5) + 8}
    hline(s, s.y - 3, 0.6)
  end

  defp groups(%{view: view} = s) do
    automatic = view.groups

    if automatic == [] do
      s
    else
      s = table_head(s)

      Enum.reduce(automatic, s, fn group, s ->
        terms = terms_text(group, s.l, view)
        terms_lines = Pdf.wrap(s.pdf, terms, mm(62), size: 8.5)
        height = max(1, length(terms_lines)) * 4 + 2.5
        s = ensure(s, height)

        s =
          s
          |> text(@left, s.y, group_title(group, s.l), font: :bold, size: 9)
          |> text(140, s.y, quantity_rate(group, view), size: 9, align: :right)
          |> text(@right, s.y, money(group.amount_cents, view), size: 9, align: :right)

        s =
          terms_lines
          |> Enum.with_index()
          |> Enum.reduce(s, fn {line, index}, s ->
            text(s, 58, s.y + index * 4, line, size: 8.5, color: {0.25, 0.25, 0.25})
          end)

        %{s | y: s.y + height}
      end)
    end
  end

  defp table_head(%{l: l} = s) do
    s
    |> text(@left, s.y, l.item, font: :bold, size: 8)
    |> text(58, s.y, l.terms, font: :bold, size: 8)
    |> text(140, s.y, l.quantity_rate, font: :bold, size: 8, align: :right)
    |> text(@right, s.y, l.amount, font: :bold, size: 8, align: :right)
    |> then(&hline(&1, &1.y + 1.6, 0.4))
    |> then(&%{&1 | y: &1.y + 6})
  end

  defp manual(%{view: %{manual: []}} = s), do: s

  defp manual(%{view: view, l: l} = s) do
    s = ensure(s, 14)
    s = %{s | y: s.y + 3}
    s = text(s, @left, s.y, String.upcase(l.added_by_hand), size: 7.5, color: {0.3, 0.3, 0.3})
    s = %{s | y: s.y + 5}

    Enum.reduce(view.manual, s, fn line, s ->
      title = "#{label(l, line.kind)} · #{line.description}"
      title_lines = Pdf.wrap(s.pdf, title, mm(120), size: 9)

      note_lines =
        if is_binary(line.note) and line.note != line.description,
          do: Pdf.wrap(s.pdf, "#{l.note}: #{line.note}", mm(150), size: 8.5),
          else: []

      height = length(title_lines) * 4 + length(note_lines) * 4 + 2.5
      s = ensure(s, height)

      s =
        title_lines
        |> Enum.with_index()
        |> Enum.reduce(s, fn {row, index}, s ->
          text(s, @left, s.y + index * 4, row, size: 9)
        end)
        |> text(@right, s.y, money(line.amount_cents, view), size: 9, align: :right)

      s =
        note_lines
        |> Enum.with_index()
        |> Enum.reduce(s, fn {row, index}, s ->
          y = s.y + (length(title_lines) + index) * 4
          text(s, @left + 4, y, row, size: 8.5, color: {0.25, 0.25, 0.25})
        end)

      %{s | y: s.y + height}
    end)
  end

  defp total(%{view: view, l: l} = s) do
    s = ensure(s, 14)
    s = hline(s, s.y, 1.0)

    s
    |> text(140, s.y + 6, l.total, font: :bold, size: 11, align: :right)
    |> text(@right, s.y + 6, money(view.total_cents, view), font: :bold, size: 11, align: :right)
    |> Map.put(:y, s.y + 14)
  end

  defp footer(%{l: l} = s) do
    s
    |> text(@left, @page_height - 12, "#{l.internal} – #{l.disclaimer}",
      size: 7,
      color: {0.35, 0.35, 0.35}
    )
    |> page_number()
  end

  # ── Text ──────────────────────────────────────────────────────────────────

  defp group_title(group, l) do
    case group.terms do
      %{"source" => "pay_item", "name" => name} -> "#{label(l, group.kind)} · #{name}"
      _terms -> label(l, group.kind)
    end
  end

  defp terms_text(%{terms: nil}, _l, _view), do: ""

  defp terms_text(%{terms: %{"source" => "pay_item"} = terms}, l, view) do
    [
      "#{money(terms["amount_cents"], view)} #{label(l, terms["unit"])}",
      terms["weekly_threshold"] &&
        String.replace(l.weekly_threshold, "%{threshold}", to_string(terms["weekly_threshold"]))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp terms_text(%{terms: %{"kind" => "fixed"} = terms}, l, view),
    do: "#{money(terms["amount_cents"], view)} #{label(l, terms["frequency"])}"

  defp terms_text(%{terms: %{"kind" => "percent_of_sales"} = terms}, l, _view),
    do: "#{percent(terms["percent_bps"])} · #{label(l, terms["sales_scope"])}"

  defp terms_text(%{terms: terms}, _l, view),
    do: money(terms["amount_cents"], view)

  defp quantity_rate(%{kind: "percent_of_sales"} = group, view),
    do: if(group.base_cents, do: money(group.base_cents, view), else: "")

  defp quantity_rate(group, view) do
    rate = if group.unit_cents, do: " × #{money(group.unit_cents, view)}", else: ""

    quantity =
      case group.quantity_divisor do
        60 -> hours(group.quantity)
        divisor when is_integer(divisor) and divisor > 1 -> "#{group.quantity}/#{divisor}"
        _one -> Integer.to_string(group.quantity)
      end

    quantity <> rate
  end

  defp hours(minutes), do: "#{div(minutes, 60)}:#{pad(rem(minutes, 60))} h"

  defp label(l, key) when is_binary(key) do
    Map.get(l, String.to_existing_atom(key), key)
  rescue
    ArgumentError -> key
  end

  defp label(_l, _key), do: ""

  @doc "Cents as an amount in the language's style with the currency code."
  def money(nil, _view), do: ""

  def money(cents, %{currency: currency, language: language}) do
    {thousands, decimal} = if language == "en", do: {",", "."}, else: {".", ","}
    sign = if cents < 0, do: "-", else: ""
    whole = cents |> abs() |> div(100) |> Integer.to_string() |> group(thousands)
    "#{sign}#{whole}#{decimal}#{pad(rem(abs(cents), 100))} #{currency}"
  end

  defp group(digits, separator) do
    digits
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.chunk_every(3)
    |> Enum.map_join(separator, &to_string/1)
    |> String.reverse()
  end

  defp percent(nil), do: ""
  defp percent(bps), do: "#{div(bps, 100)},#{pad(rem(bps, 100))}%"

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp date(%Date{} = date), do: "#{pad(date.day)}/#{pad(date.month)}/#{date.year}"

  # ── Drawing ───────────────────────────────────────────────────────────────

  defp text(s, x, y, value, opts),
    do: %{s | pdf: Pdf.text(s.pdf, mm(x), mm(@page_height - y), value, opts)}

  defp hline(s, y, width) do
    %{
      s
      | pdf:
          Pdf.line(s.pdf, mm(@left), mm(@page_height - y), mm(@right), mm(@page_height - y),
            line_width: width
          )
    }
  end

  defp ensure(s, height) do
    if s.y + height > @page_height - @bottom do
      s = page_number(s)
      %{s | pdf: Pdf.add_page(s.pdf), page: s.page + 1, y: 18}
    else
      s
    end
  end

  defp page_number(%{l: l} = s),
    do:
      text(s, @right, @page_height - 12, "#{l.page} #{s.page}",
        size: 7,
        align: :right,
        color: {0.35, 0.35, 0.35}
      )

  defp mm(value), do: value * @mm
end
