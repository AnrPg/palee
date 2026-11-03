defmodule Palee.Ranks.Domain.CertificatePdfTest do
  @moduledoc "ADR-377 amendment (option Γ): the diploma with the box logo and the coach's signature."

  use ExUnit.Case, async: true

  alias Palee.Pdf.Image
  alias Palee.Ranks.Domain.CertificatePdf
  alias Palee.TestSupport.PngFixture

  @view %{
    box: "Box Kypseli",
    person: "Μαρία Κ.",
    ladder: "BJJ ενηλίκων",
    rank: "Μπλε ζώνη",
    color: "blue",
    stripes: 2,
    awarded_on: ~D[2026-11-03],
    awarded_by: "Νίκος Π.",
    number: "R-2026-3F9A1C2B",
    revoked: false
  }

  setup do
    {:ok, logo} = Image.parse(PngFixture.png(64, 64, color: :rgb))
    {:ok, signature} = Image.parse(PngFixture.png(300, 100))
    %{fonts: Palee.Pdf.Fonts.sans(), logo: logo, signature: signature}
  end

  test "logo and signature are drawn as images; the texts stay", ctx do
    view = Map.merge(@view, %{logo: ctx.logo, signature: ctx.signature})
    pdf = CertificatePdf.render(view, ctx.fonts)

    # The logo (no mask) and the signature with its soft mask.
    assert length(Regex.scan(~r{/Subtype /Image}, pdf)) == 3
    assert pdf =~ "/SMask"
    assert page_content(pdf) =~ " cm /Im1 Do"
    assert page_content(pdf) =~ " cm /Im2 Do"

    texts = CertificatePdf.texts(view, ctx.fonts)
    assert "Box Kypseli" in texts
    assert "Νίκος Π. · Coach" in texts
    assert "Αριθμός διπλώματος R-2026-3F9A1C2B" in texts
    refute "Ανακλήθηκε" in texts
  end

  test "the signature fits its place above the line, the logo above the name", ctx do
    pdf =
      CertificatePdf.render(
        Map.merge(@view, %{logo: ctx.logo, signature: ctx.signature}),
        ctx.fonts
      )

    page = page_content(pdf)

    # Logo 64 × 64 px into 120 × 64 pt; signature 300 × 100 px into 200 × 70 pt.
    assert page =~ "64 0 0 64 265.64 752 cm /Im1 Do"
    assert page =~ "200 0 0 66.667 197.64 222 cm /Im2 Do"
  end

  test "without a logo or a signature: only the name and an empty line", ctx do
    pdf = CertificatePdf.render(Map.merge(@view, %{logo: nil, signature: nil}), ctx.fonts)
    refute pdf =~ "/Subtype /Image"
    assert "Νίκος Π. · Coach" in CertificatePdf.texts(@view, ctx.fonts)
    assert page_content(pdf) =~ " l S Q"
  end

  test "a withdrawn diploma still says so; no awarding coach, no line", ctx do
    view = %{@view | revoked: true, awarded_by: nil}
    texts = CertificatePdf.texts(Map.put(view, :signature, ctx.signature), ctx.fonts)
    assert "Ανακλήθηκε" in texts
    refute Enum.any?(texts, &String.ends_with?(&1, "· Coach"))

    refute CertificatePdf.render(Map.put(view, :signature, ctx.signature), ctx.fonts) =~
             "/Subtype /Image"
  end

  # The first page's content stream, inflated.
  defp page_content(pdf) do
    [_, stream] =
      Regex.run(
        ~r/5 0 obj\n<< \/Length \d+ \/Filter \/FlateDecode  >>\nstream\n(.*?)\nendstream/s,
        pdf
      )

    :zlib.uncompress(stream)
  end
end
