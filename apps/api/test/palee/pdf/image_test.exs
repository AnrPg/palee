defmodule Palee.Pdf.ImageTest do
  @moduledoc "ADR-377 amendment: JPEG and PNG images in `Palee.Pdf`, without an image library."

  use ExUnit.Case, async: true

  alias Palee.Pdf
  alias Palee.Pdf.Image
  alias Palee.TestSupport.PngFixture

  # SOI, an APP0 segment, then a baseline frame header: 3 components, 40 × 30.
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xFF, 0xC0, 0, 17,
          8, 0, 30, 0, 40, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1, 0xFF, 0xD9>>

  test "a JPEG goes in as it is" do
    assert {:ok,
            %Image{width: 40, height: 30, filter: "DCTDecode", color_space: "/DeviceRGB"} = image} =
             Image.parse(@jpeg)

    assert image.data == @jpeg
    assert image.smask == nil
  end

  test "an RGB PNG keeps its compressed data and lets the reader undo the predictors" do
    png = PngFixture.png(12, 5, color: :rgb, filter: 4)

    assert {:ok, %Image{width: 12, height: 5, filter: "FlateDecode", smask: nil} = image} =
             Image.parse(png)

    assert image.color_space == "/DeviceRGB"
    assert image.decode_parms =~ "/Predictor 15 /Colors 3 /BitsPerComponent 8 /Columns 12"
  end

  test "a palette PNG without transparency becomes an indexed image" do
    assert {:ok, %Image{color_space: "[/Indexed /DeviceRGB 2 <000000C81E1E141E78>]"}} =
             Image.parse(PngFixture.png(6, 4, color: :palette))
  end

  for filter <- 0..4 do
    test "an RGBA PNG (filter #{filter}) is split into colour and a soft mask" do
      png = PngFixture.png(9, 6, color: :rgba, filter: unquote(filter))
      pixels = PngFixture.pixels(:rgba, 9, 6)

      assert {:ok, %Image{smask: %Image{} = mask} = image} = Image.parse(png)

      assert :zlib.uncompress(image.data) ==
               for(<<r, g, b, _a <- pixels>>, into: <<>>, do: <<r, g, b>>)

      assert :zlib.uncompress(mask.data) ==
               for(<<_r, _g, _b, a <- pixels>>, into: <<>>, do: <<a>>)

      assert mask.color_space == "/DeviceGray"
    end
  end

  test "grey with alpha, and a palette with a transparent entry" do
    assert {:ok, %Image{color_space: "/DeviceGray", smask: %Image{}}} =
             Image.parse(PngFixture.png(5, 3, color: :grey_alpha, filter: 1))

    assert {:ok, %Image{color_space: "/DeviceRGB", smask: %Image{data: alpha}}} =
             Image.parse(PngFixture.png(3, 1, color: :palette, trns: true))

    # Pixel indexes 0, 1, 2: the first is transparent.
    assert :zlib.uncompress(alpha) == <<0, 255, 255>>
  end

  test "what cannot be embedded is refused" do
    for bytes <- [
          "RIFF\0\0\0\0WEBPVP8 ",
          "GIF89a",
          PngFixture.png(4, 4, interlace: true),
          binary_part(PngFixture.png(4, 4), 0, 30),
          <<0xFF, 0xD8, 0xFF, 0xD9>>,
          ""
        ] do
      assert Image.parse(bytes) == {:error, :unsupported_image}
    end
  end

  test "fits the box keeping the proportions" do
    {:ok, image} = Image.parse(PngFixture.png(300, 100))
    assert {200.0, height} = Image.fit(image, 200, 70)
    assert_in_delta height, 66.667, 0.001
    assert Image.fit(image, 90, 90) == {90.0, 30.0}
  end

  test "a page with images has them as XObjects, with the mask linked" do
    {:ok, png} = Image.parse(PngFixture.png(10, 4))
    {:ok, jpeg} = Image.parse(@jpeg)

    pdf =
      Pdf.new(%{regular: Palee.Pdf.Fonts.sans().regular})
      |> Pdf.text(50, 50, "x")
      |> Pdf.image(png, 100, 100, 50, 20)
      |> Pdf.image(jpeg, 100, 200, 40, 30)

    assert Pdf.image_count(pdf) == 2
    file = Pdf.render(pdf)
    assert file =~ "/XObject << /Im1 "
    assert file =~ "/Im2 "

    [_, stream] =
      Regex.run(
        ~r/5 0 obj\n<< \/Length \d+ \/Filter \/FlateDecode  >>\nstream\n(.*?)\nendstream/s,
        file
      )

    assert :zlib.uncompress(stream) =~ "50 0 0 20 100 100 cm /Im1 Do"
    assert file =~ ~r{/Subtype /Image /Width 10 .* /SMask \d+ 0 R}
    assert file =~ "/Filter /DCTDecode"
    assert [_ | _] = Regex.scan(~r/startxref/, file)
  end
end
