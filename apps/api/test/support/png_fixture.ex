defmodule Palee.TestSupport.PngFixture do
  @moduledoc "Small PNG files built in the test (no image library): RGBA, RGB, grey + alpha and palette."

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc """
  A `width` × `height` PNG. `color`: `:rgba` (default), `:rgb`, `:grey_alpha`
  or `:palette` (with `trns: true` for a transparent first entry);
  `filter`: the PNG row filter used (0–4); `interlace: true` marks it
  interlaced (the data is then not really Adam7, which is enough to refuse it).
  """
  def png(width, height, opts \\ []) do
    color = Keyword.get(opts, :color, :rgba)
    filter = Keyword.get(opts, :filter, 0)
    {type, bpp} = color_type(color)

    {rows, _prior} =
      Enum.map_reduce(0..(height - 1), :binary.copy(<<0>>, width * bpp), fn y, prior ->
        line = row(color, width, y)
        {[filter, encode(line, prior, bpp, filter)], line}
      end)

    IO.iodata_to_binary([
      @signature,
      chunk(
        "IHDR",
        <<width::32, height::32, 8, type, 0, 0, if(opts[:interlace], do: 1, else: 0)>>
      ),
      if(color == :palette, do: chunk("PLTE", <<0, 0, 0, 200, 30, 30, 20, 30, 120>>), else: []),
      if(color == :palette and opts[:trns], do: chunk("tRNS", <<0>>), else: []),
      chunk("IDAT", :zlib.compress(IO.iodata_to_binary(rows))),
      chunk("IEND", <<>>)
    ])
  end

  @doc "The raw pixels `png/3` encodes (for checking the decoder)."
  def pixels(color, width, height),
    do: IO.iodata_to_binary(for y <- 0..(height - 1), do: row(color, width, y))

  defp color_type(:rgba), do: {6, 4}
  defp color_type(:rgb), do: {2, 3}
  defp color_type(:grey_alpha), do: {4, 2}
  defp color_type(:palette), do: {3, 1}

  defp row(color, width, y) do
    IO.iodata_to_binary(
      for x <- 0..(width - 1) do
        v = rem(x * 7 + y * 13, 256)

        case color do
          :rgba ->
            <<v, rem(v + 40, 256), rem(v * 3, 256), if(rem(x + y, 3) == 0, do: 0, else: 255)>>

          :rgb ->
            <<v, rem(v + 40, 256), rem(v * 3, 256)>>

          :grey_alpha ->
            <<v, rem(v * 5, 256)>>

          :palette ->
            <<rem(x + y, 3)>>
        end
      end
    )
  end

  # A row as the PNG filter `filter` writes it, against the row above.
  defp encode(line, _prior, _bpp, 0), do: line

  defp encode(line, prior, bpp, filter) do
    bytes = line |> :binary.bin_to_list() |> List.to_tuple()
    up = prior |> :binary.bin_to_list() |> List.to_tuple()

    for i <- 0..(tuple_size(bytes) - 1), into: <<>> do
      a = if i >= bpp, do: elem(bytes, i - bpp), else: 0
      c = if i >= bpp, do: elem(up, i - bpp), else: 0
      <<Bitwise.band(elem(bytes, i) - predict(filter, a, elem(up, i), c) + 256, 0xFF)>>
    end
  end

  defp predict(1, a, _b, _c), do: a
  defp predict(2, _a, b, _c), do: b
  defp predict(3, a, b, _c), do: div(a + b, 2)

  defp predict(4, a, b, c) do
    p = a + b - c
    {pa, pb, pc} = {abs(p - a), abs(p - b), abs(p - c)}

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end

  defp chunk(type, data) do
    [<<byte_size(data)::32>>, type, data, <<:erlang.crc32([type, data])::32>>]
  end
end
