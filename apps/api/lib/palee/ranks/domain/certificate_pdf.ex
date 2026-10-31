defmodule Palee.Ranks.Domain.CertificatePdf do
  @moduledoc """
  «Δίπλωμα» of a rank award as an A4 landscape-feel PDF page (ADR-377),
  drawn with `Palee.Pdf` and Liberation Sans (Greek and Latin): the box,
  the person, the ladder and rank (with stripes), the date, who awarded it
  and the diploma number. A withdrawn award prints «Ανακλήθηκε».

  `view`: `%{box, person, ladder, rank, color, stripes, awarded_on,
  awarded_by, number, revoked}`. Colours are the belt palette's print
  values; the screen uses the theme's `--belt-*` tokens.
  """

  alias Palee.Pdf

  @print_colors %{
    "white" => {0.95, 0.95, 0.95},
    "grey" => {0.6, 0.6, 0.6},
    "yellow" => {0.96, 0.8, 0.1},
    "orange" => {0.95, 0.5, 0.1},
    "green" => {0.2, 0.6, 0.3},
    "blue" => {0.15, 0.35, 0.75},
    "purple" => {0.45, 0.25, 0.6},
    "brown" => {0.45, 0.3, 0.15},
    "red" => {0.8, 0.15, 0.15},
    "black" => {0.1, 0.1, 0.1},
    "pink" => {0.95, 0.55, 0.7}
  }

  def render(view, fonts) do
    view |> layout(fonts) |> Pdf.render(title: "Δίπλωμα #{view.number}", author: view.box)
  end

  @doc "The texts drawn, in order (for checks without parsing the PDF)."
  def texts(view, fonts), do: view |> layout(fonts) |> Pdf.texts()

  defp layout(view, fonts) do
    {width, _height} = Pdf.a4()
    center = width / 2

    fonts
    |> Pdf.new()
    |> centered(center, 760, view.box, :bold, 18)
    |> centered(center, 700, "ΔΙΠΛΩΜΑ", :bold, 30)
    |> centered(center, 650, "Απονέμεται σε", :regular, 13)
    |> centered(center, 615, view.person, :bold, 24)
    |> centered(center, 570, view.ladder, :regular, 14)
    |> centered(center, 535, rank_line(view), :bold, 20)
    |> belt(center, view.color, view.stripes)
    |> centered(
      center,
      420,
      "Ημερομηνία: #{Calendar.strftime(view.awarded_on, "%d/%m/%Y")}",
      :regular,
      12
    )
    |> centered(center, 400, awarded_by(view.awarded_by), :regular, 12)
    |> centered(center, 120, "Αριθμός διπλώματος #{view.number}", :regular, 10)
    |> revoked(center, view.revoked)
  end

  defp rank_line(%{rank: rank, stripes: stripes}) when stripes > 0,
    do: "#{rank} · #{stripes} #{if stripes == 1, do: "ρίγα", else: "ρίγες"}"

  defp rank_line(%{rank: rank}), do: rank

  defp awarded_by(nil), do: ""
  defp awarded_by(name), do: "Απονομή: #{name}"

  defp belt(pdf, _center, nil, _stripes), do: pdf

  defp belt(pdf, center, color, stripes) do
    fill = Map.get(@print_colors, color, {0.5, 0.5, 0.5})
    width = 260

    pdf
    |> Pdf.rect(center - width / 2, 470, width, 26, color: fill)
    |> Pdf.rect(center - width / 2, 470, width, 26, fill: false, stroke: true, line_width: 0.8)
    |> stripes(center + width / 2 - 70, stripes)
  end

  defp stripes(pdf, _x, 0), do: pdf

  defp stripes(pdf, x, count) do
    Enum.reduce(1..count, pdf, fn i, acc ->
      Pdf.rect(acc, x + i * 10, 470, 5, 26, color: {0.95, 0.95, 0.95})
    end)
  end

  defp revoked(pdf, _center, false), do: pdf

  defp revoked(pdf, center, true),
    do: centered(pdf, center, 300, "Ανακλήθηκε", :bold, 22)

  defp centered(pdf, _center, _y, nil, _font, _size), do: pdf
  defp centered(pdf, _center, _y, "", _font, _size), do: pdf

  defp centered(pdf, center, y, text, font, size) do
    width = Pdf.text_width(pdf, text, font: font, size: size)
    Pdf.text(pdf, center - width / 2, y, text, font: font, size: size)
  end
end
