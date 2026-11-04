defmodule Palee.Pdf.Image do
  @moduledoc """
  A raster image as a PDF image XObject (ADR-377 addendum: the diploma's box
  logo and coach signature), read from the bytes of a JPEG or PNG file with
  no image library:

    * JPEG goes in as it is (`DCTDecode`); only its frame header is read.
    * PNG without transparency goes in as its own compressed data, with the
      PNG predictors the PDF reader undoes (`FlateDecode`, `Predictor 15`);
      a palette becomes an `Indexed` colour space.
    * PNG with transparency (grey + alpha, RGBA, or a palette with `tRNS`),
      8 bits per sample, is unfiltered here and split into the colour image
      and a soft mask, so a transparent signature sits on the paper.

  Anything else (WebP, GIF, interlaced or 16-bit PNG with alpha, broken
  files, more than `max_pixels/0` pixels to unfilter) answers
  `{:error, :unsupported_image}`; callers then leave the image out.
  """

  @enforce_keys [:width, :height, :color_space, :bits, :filter, :data]
  defstruct [
    :width,
    :height,
    :color_space,
    :bits,
    :filter,
    :data,
    decode_parms: nil,
    decode: nil,
    smask: nil
  ]

  @type t :: %__MODULE__{}

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @max_pixels 2_000_000

  @doc "Largest image (in pixels) whose transparency is unpacked here."
  def max_pixels, do: @max_pixels

  @doc "Reads a JPEG or PNG file."
  @spec parse(binary()) :: {:ok, t()} | {:error, :unsupported_image}
  def parse(<<0xFF, 0xD8, rest::binary>> = jpeg), do: jpeg(rest, jpeg)
  def parse(<<@png_signature, rest::binary>>), do: png(rest)
  def parse(_other), do: {:error, :unsupported_image}

  @doc """
  The largest `{width, height}` with the image's proportions that fits in
  `max_width` × `max_height` points.
  """
  def fit(%__MODULE__{width: width, height: height}, max_width, max_height) do
    scale = min(max_width / width, max_height / height)
    {width * scale, height * scale}
  end

  # ── JPEG ──────────────────────────────────────────────────────────────────

  # Start-of-frame markers (baseline, progressive, lossless, arithmetic).
  @sof [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]

  defp jpeg(<<0xFF, marker, length::16, segment::binary>>, file) when marker in @sof do
    case segment do
      <<8, height::16, width::16, components, _rest::binary>>
      when length >= 8 and width > 0 and height > 0 and components in [1, 3, 4] ->
        {:ok,
         %__MODULE__{
           width: width,
           height: height,
           bits: 8,
           filter: "DCTDecode",
           data: file,
           color_space: jpeg_color_space(components),
           # Adobe writes CMYK JPEGs inverted.
           decode: if(components == 4, do: "[1 0 1 0 1 0 1 0]")
         }}

      _other ->
        {:error, :unsupported_image}
    end
  end

  # Fill bytes before a marker.
  defp jpeg(<<0xFF, 0xFF, rest::binary>>, file), do: jpeg(<<0xFF, rest::binary>>, file)

  # Markers without a length.
  defp jpeg(<<0xFF, marker, rest::binary>>, file) when marker in 0xD0..0xD7 or marker == 0x01,
    do: jpeg(rest, file)

  defp jpeg(<<0xFF, marker, length::16, rest::binary>>, file)
       when marker not in [0xD9, 0xDA] and length >= 2 and byte_size(rest) >= length - 2 do
    <<_skip::binary-size(length - 2), next::binary>> = rest
    jpeg(next, file)
  end

  defp jpeg(_other, _file), do: {:error, :unsupported_image}

  defp jpeg_color_space(1), do: "/DeviceGray"
  defp jpeg_color_space(3), do: "/DeviceRGB"
  defp jpeg_color_space(4), do: "/DeviceCMYK"

  # ── PNG ───────────────────────────────────────────────────────────────────

  defp png(rest) do
    with {:ok, chunks} <- chunks(rest, %{idat: []}),
         {:ok, header} <- header(chunks) do
      chunks = %{chunks | idat: chunks.idat |> Enum.reverse() |> IO.iodata_to_binary()}
      png_image(header, chunks)
    end
  end

  defp chunks(<<length::32, type::binary-size(4), rest::binary>>, acc)
       when byte_size(rest) >= length + 4 do
    <<data::binary-size(length), _crc::32, next::binary>> = rest

    case type do
      "IEND" -> {:ok, acc}
      "IDAT" -> chunks(next, %{acc | idat: [data | acc.idat]})
      "IHDR" -> chunks(next, Map.put(acc, :ihdr, data))
      "PLTE" -> chunks(next, Map.put(acc, :plte, data))
      "tRNS" -> chunks(next, Map.put(acc, :trns, data))
      _ancillary -> chunks(next, acc)
    end
  end

  defp chunks(_truncated, _acc), do: {:error, :unsupported_image}

  defp header(%{ihdr: <<width::32, height::32, bits, color, 0, 0, interlace>>})
       when width > 0 and height > 0 and interlace in [0, 1] do
    {:ok, %{width: width, height: height, bits: bits, color: color, interlace: interlace}}
  end

  defp header(_chunks), do: {:error, :unsupported_image}

  # Interlaced images would need de-interlacing here; none is embedded.
  defp png_image(%{interlace: 1}, _chunks), do: {:error, :unsupported_image}

  # Grey or RGB without alpha: the PNG data as it is (a tRNS colour key is ignored).
  defp png_image(%{color: color, bits: bits} = header, chunks)
       when color in [0, 2] and bits in [1, 2, 4, 8, 16] do
    colors = if color == 0, do: 1, else: 3
    space = if color == 0, do: "/DeviceGray", else: "/DeviceRGB"
    {:ok, passthrough(header, chunks.idat, space, colors)}
  end

  # A palette without transparency.
  defp png_image(%{color: 3, bits: bits} = header, %{plte: plte} = chunks)
       when bits in [1, 2, 4, 8] and not is_map_key(chunks, :trns) do
    {:ok, passthrough(header, chunks.idat, indexed(plte), 1)}
  end

  # Grey + alpha, RGBA, or a palette with transparency: unpacked here.
  defp png_image(%{color: color, bits: 8, width: width, height: height} = header, chunks)
       when color in [3, 4, 6] and width * height <= @max_pixels do
    with {:ok, raw} <- inflate(chunks.idat),
         {:ok, pixels} <- unfilter(raw, header, channels(color)),
         {:ok, color_data, alpha, space} <- split(pixels, color, chunks) do
      {:ok,
       %__MODULE__{
         width: width,
         height: height,
         bits: 8,
         filter: "FlateDecode",
         color_space: space,
         data: :zlib.compress(color_data),
         smask: %__MODULE__{
           width: width,
           height: height,
           bits: 8,
           filter: "FlateDecode",
           color_space: "/DeviceGray",
           data: :zlib.compress(alpha)
         }
       }}
    end
  end

  defp png_image(_header, _chunks), do: {:error, :unsupported_image}

  defp passthrough(header, idat, space, colors) do
    %__MODULE__{
      width: header.width,
      height: header.height,
      bits: header.bits,
      filter: "FlateDecode",
      color_space: space,
      data: idat,
      decode_parms:
        "<< /Predictor 15 /Colors #{colors} /BitsPerComponent #{header.bits} /Columns #{header.width} >>"
    }
  end

  defp indexed(plte) do
    count = div(byte_size(plte), 3)
    "[/Indexed /DeviceRGB #{count - 1} <#{Base.encode16(binary_part(plte, 0, count * 3))}>]"
  end

  defp channels(3), do: 1
  defp channels(4), do: 2
  defp channels(6), do: 4

  defp inflate(data) do
    {:ok, :zlib.uncompress(data)}
  rescue
    _error -> {:error, :unsupported_image}
  end

  # PNG filters, 8 bits per sample: each row starts with its filter type.
  defp unfilter(raw, %{width: width, height: height}, bpp) do
    stride = width * bpp

    if byte_size(raw) < (stride + 1) * height do
      {:error, :unsupported_image}
    else
      {rows, _prior} =
        Enum.map_reduce(0..(height - 1), :binary.copy(<<0>>, stride), fn index, prior ->
          <<type, line::binary-size(stride)>> = binary_part(raw, index * (stride + 1), stride + 1)
          row = unfilter_row(type, line, prior, bpp)
          {row, row}
        end)

      if Enum.any?(rows, &(&1 == :error)),
        do: {:error, :unsupported_image},
        else: {:ok, IO.iodata_to_binary(rows)}
    end
  end

  defp unfilter_row(0, line, _prior, _bpp), do: line

  defp unfilter_row(2, line, prior, _bpp) do
    line
    |> :binary.bin_to_list()
    |> Enum.zip_with(:binary.bin_to_list(prior), &band(&1 + &2))
    |> :binary.list_to_bin()
  end

  defp unfilter_row(type, line, prior, bpp) when type in [1, 3, 4] do
    up = :binary.bin_to_list(prior)

    {out, _left, _upleft} =
      line
      |> :binary.bin_to_list()
      |> Enum.zip(up)
      |> Enum.with_index()
      |> Enum.reduce({[], :queue.new(), :queue.new()}, fn {{byte, b}, index}, {acc, lefts, ups} ->
        {a, lefts} = take_back(lefts, index, bpp)
        {c, ups} = take_back(ups, index, bpp)
        value = band(byte + predict(type, a, b, c))
        {[value | acc], :queue.in(value, lefts), :queue.in(b, ups)}
      end)

    out |> Enum.reverse() |> :binary.list_to_bin()
  end

  defp unfilter_row(_type, _line, _prior, _bpp), do: :error

  # The byte `bpp` positions back (0 before the first pixel).
  defp take_back(queue, index, bpp) when index < bpp, do: {0, queue}

  defp take_back(queue, _index, _bpp) do
    {{:value, value}, queue} = :queue.out(queue)
    {value, queue}
  end

  defp predict(1, a, _b, _c), do: a
  defp predict(3, a, b, _c), do: div(a + b, 2)

  defp predict(4, a, b, c) do
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end

  defp band(value), do: Bitwise.band(value, 0xFF)

  defp split(pixels, 6, _chunks) do
    {:ok, for(<<r, g, b, _a <- pixels>>, into: <<>>, do: <<r, g, b>>),
     for(<<_r, _g, _b, a <- pixels>>, into: <<>>, do: <<a>>), "/DeviceRGB"}
  end

  defp split(pixels, 4, _chunks) do
    {:ok, for(<<v, _a <- pixels>>, into: <<>>, do: <<v>>),
     for(<<_v, a <- pixels>>, into: <<>>, do: <<a>>), "/DeviceGray"}
  end

  defp split(pixels, 3, %{plte: plte} = chunks) do
    count = div(byte_size(plte), 3)
    palette = for <<r, g, b <- binary_part(plte, 0, count * 3)>>, do: <<r, g, b>>
    palette = List.to_tuple(palette)
    trns = Map.get(chunks, :trns, <<>>)
    alphas = trns |> :binary.bin_to_list() |> List.to_tuple()

    if Enum.any?(:binary.bin_to_list(pixels), &(&1 >= count)) do
      {:error, :unsupported_image}
    else
      color = for <<index <- pixels>>, into: <<>>, do: elem(palette, index)

      alpha =
        for <<index <- pixels>>,
          into: <<>>,
          do: <<if(index < tuple_size(alphas), do: elem(alphas, index), else: 255)>>

      {:ok, color, alpha, "/DeviceRGB"}
    end
  end

  defp split(_pixels, _color, _chunks), do: {:error, :unsupported_image}
end
