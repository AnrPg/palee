defmodule Palee.Ranks.Domain.CertificatePdf do
  @moduledoc """
  «Δίπλωμα» of a rank award as an A4 landscape-feel PDF page (ADR-377),
  drawn with `Palee.Pdf` and Liberation Sans (Greek and Latin): the box,
  the person, the ladder and rank (with stripes), the date, who awarded it
  and the diploma number. A withdrawn award prints «Ανακλήθηκε».

  Option Γ (ADR-377 addendum): the box logo above its name when there is
  one, and the awarding coach's signature image above a line with
  «<name> · Coach» (an empty line when the coach has no signature).

  `view`: `%{box, person, ladder, rank, color, stripes, awarded_on,
  awarded_by, number, revoked}` and optionally `logo` and `signature`
  (`Palee.Pdf.Image` or nil), each scaled to fit its place. Colours are the
  belt palette's print values; the screen uses the theme's `--belt-*`
  tokens.
  """

  alias Palee.Pdf
  alias Palee.Pdf.Image

  @logo_box {120, 64}
  @signature_box {200, 70}
  @signature_line 220

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
    |> logo(center, Map.get(view, :logo))
    |> centered(center, 730, view.box, :bold, 18)
    |> centered(center, 680, "ΔΙΠΛΩΜΑ", :bold, 30)
    |> centered(center, 635, "Απονέμεται σε", :regular, 13)
    |> centered(center, 600, view.person, :bold, 24)
    |> centered(center, 560, view.ladder, :regular, 14)
    |> centered(center, 525, rank_line(view), :bold, 20)
    |> belt(center, view.color, view.stripes)
    |> centered(
      center,
      410,
      "Ημερομηνία: #{Calendar.strftime(view.awarded_on, "%d/%m/%Y")}",
      :regular,
      12
    )
    |> signature(center, view.awarded_by, Map.get(view, :signature))
    |> centered(center, 120, "Αριθμός διπλώματος #{view.number}", :regular, 10)
    |> revoked(center, view.revoked)
  end

  defp rank_line(%{rank: rank, stripes: stripes}) when stripes > 0,
    do: "#{rank} · #{stripes} #{if stripes == 1, do: "ρίγα", else: "ρίγες"}"

  defp rank_line(%{rank: rank}), do: rank

  # Centred above the box's name, bottom at 752.
  defp logo(pdf, _center, nil), do: pdf

  defp logo(pdf, center, %Image{} = image) do
    {max_width, max_height} = @logo_box
    {width, height} = Image.fit(image, max_width, max_height)
    Pdf.image(pdf, image, center - width / 2, 752, width, height)
  end

  # The coach's line: the signature image (when there is one) standing on
  # it, and «<name> · Coach» under it. No awarding coach, no line.
  defp signature(pdf, _center, nil, _image), do: pdf

  defp signature(pdf, center, name, image) do
    half = elem(@signature_box, 0) / 2 + 10

    pdf
    |> signature_image(center, image)
    |> Pdf.line(center - half, @signature_line, center + half, @signature_line, line_width: 0.6)
    |> centered(center, @signature_line - 16, "#{name} · Coach", :regular, 12)
  end

  defp signature_image(pdf, _center, nil), do: pdf

  defp signature_image(pdf, center, %Image{} = image) do
    {max_width, max_height} = @signature_box
    {width, height} = Image.fit(image, max_width, max_height)
    Pdf.image(pdf, image, center - width / 2, @signature_line + 2, width, height)
  end

  defp belt(pdf, _center, nil, _stripes), do: pdf

  defp belt(pdf, center, color, stripes) do
    fill = Map.get(@print_colors, color, {0.5, 0.5, 0.5})
    width = 260

    pdf
    |> Pdf.rect(center - width / 2, 460, width, 26, color: fill)
    |> Pdf.rect(center - width / 2, 460, width, 26, fill: false, stroke: true, line_width: 0.8)
    |> stripes(center + width / 2 - 70, stripes)
  end

  defp stripes(pdf, _x, 0), do: pdf

  defp stripes(pdf, x, count) do
    Enum.reduce(1..count, pdf, fn i, acc ->
      Pdf.rect(acc, x + i * 10, 460, 5, 26, color: {0.95, 0.95, 0.95})
    end)
  end

  defp revoked(pdf, _center, false), do: pdf

  defp revoked(pdf, center, true),
    do: centered(pdf, center, 330, "Ανακλήθηκε", :bold, 22)

  defp centered(pdf, _center, _y, nil, _font, _size), do: pdf
  defp centered(pdf, _center, _y, "", _font, _size), do: pdf

  defp centered(pdf, center, y, text, font, size) do
    width = Pdf.text_width(pdf, text, font: font, size: size)
    Pdf.text(pdf, center - width / 2, y, text, font: font, size: size)
  end
end
