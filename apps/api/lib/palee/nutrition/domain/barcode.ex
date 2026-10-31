defmodule Palee.Nutrition.Domain.Barcode do
  @moduledoc """
  Product barcodes a phone camera reads (ADR-376): EAN-13, EAN-8, UPC-A
  (12 digits, looked up as its EAN-13 with a leading zero) and GTIN-14.
  The last digit is the GS1 check digit, so a misread is caught before any
  lookup. Codes a shop prints itself (GS1 prefixes 02 and 20–29, e.g. a
  weighed cheese with its price inside) name no product anywhere and go
  straight to the manual entry.
  """

  @doc """
  `{:ok, code}` normalised (digits only, UPC-A as EAN-13),
  `{:in_store, code}` for a shop's own code, or `{:error, :invalid_barcode}`.
  """
  def parse(raw) when is_binary(raw) do
    digits = String.replace(raw, ~r/[\s-]/, "")

    cond do
      not Regex.match?(~r/^[0-9]+$/, digits) -> {:error, :invalid_barcode}
      byte_size(digits) not in [8, 12, 13, 14] -> {:error, :invalid_barcode}
      not check_digit_ok?(digits) -> {:error, :invalid_barcode}
      true -> classify(normalize(digits))
    end
  end

  def parse(_raw), do: {:error, :invalid_barcode}

  defp normalize(digits) when byte_size(digits) == 12, do: "0" <> digits
  defp normalize(digits), do: digits

  defp classify(code) when byte_size(code) == 13 do
    if in_store?(code), do: {:in_store, code}, else: {:ok, code}
  end

  defp classify(code), do: {:ok, code}

  defp in_store?("02" <> _rest), do: true
  defp in_store?("2" <> _rest), do: true
  defp in_store?(_code), do: false

  @doc "Whether the GS1 check digit (last digit) matches."
  def check_digit_ok?(digits) do
    {body, [check]} =
      digits |> String.graphemes() |> Enum.map(&String.to_integer/1) |> Enum.split(-1)

    sum =
      body
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.reduce(0, fn {digit, i}, acc -> acc + if(rem(i, 2) == 0, do: digit * 3, else: digit) end)

    rem(10 - rem(sum, 10), 10) == check
  end
end
