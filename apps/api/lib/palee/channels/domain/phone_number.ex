defmodule Palee.Channels.Domain.PhoneNumber do
  @moduledoc """
  Mobile numbers in E.164 (ADR-348 §4). A number typed in the box's own
  country may leave out the country code («69…» in Greece, «9…» in
  Cyprus); `00` and `+` prefixes, spaces, dots, dashes, slashes and
  brackets are accepted. Greek and Cypriot numbers must be mobiles, since
  only a mobile receives SMS, Viber or WhatsApp.

  Countries known here are those Palee serves first; any other number is
  accepted when it is already international and has 8–15 digits.
  """

  # country => {calling code, national length, mobile pattern}
  @countries %{
    "GR" => {"30", 10, ~r/^69[0-9]{8}$/},
    "CY" => {"357", 8, ~r/^9[4-9][0-9]{6}$/},
    "DE" => {"49", nil, ~r/^1[5-7][0-9]{8,9}$/},
    "AT" => {"43", nil, ~r/^6[5-9][0-9]{7,11}$/},
    "IT" => {"39", nil, ~r/^3[0-9]{8,9}$/},
    "FR" => {"33", 9, ~r/^[67][0-9]{8}$/},
    "ES" => {"34", 9, ~r/^[67][0-9]{8}$/},
    "NL" => {"31", 9, ~r/^6[0-9]{8}$/},
    "BE" => {"32", 9, ~r/^4[5-9][0-9]{7}$/},
    "GB" => {"44", 10, ~r/^7[0-9]{9}$/},
    "BG" => {"359", 9, ~r/^(8[789]|98)[0-9]{7}$/},
    "RO" => {"40", 9, ~r/^7[0-9]{8}$/}
  }

  @calling_codes Map.new(@countries, fn {country, {code, _length, _mobile}} -> {code, country} end)

  def countries, do: @countries |> Map.keys() |> Enum.sort()

  @doc """
  `{:ok, "+30…"}` or `{:error, :invalid_phone}`. `default_country` is the
  box's country, used when the number has no country code.
  """
  @spec normalize(term(), String.t()) :: {:ok, String.t()} | {:error, :invalid_phone}
  def normalize(phone, default_country \\ "GR")

  def normalize(phone, default_country) when is_binary(phone) do
    cleaned = String.replace(phone, ~r/[\s().\-\/]/u, "")

    cleaned
    |> international(default_country)
    |> validate()
  end

  def normalize(_phone, _default_country), do: {:error, :invalid_phone}

  defp international("+" <> digits, _country), do: {:ok, digits}
  defp international("00" <> digits, _country), do: {:ok, digits}

  defp international(national, country) do
    case Map.get(@countries, country) do
      {code, _length, _mobile} -> {:ok, code <> String.trim_leading(national, "0")}
      nil -> {:error, :invalid_phone}
    end
  end

  defp validate({:ok, digits}) do
    if digits =~ ~r/^[1-9][0-9]{7,14}$/ and mobile?(digits),
      do: {:ok, "+" <> digits},
      else: {:error, :invalid_phone}
  end

  defp validate(error), do: error

  # A number of a known country must be one of its mobiles.
  defp mobile?(digits) do
    case known_country(digits) do
      nil ->
        true

      {code, country} ->
        {^code, length, pattern} = Map.fetch!(@countries, country)
        national = binary_part(digits, byte_size(code), byte_size(digits) - byte_size(code))
        (is_nil(length) or byte_size(national) == length) and national =~ pattern
    end
  end

  defp known_country(digits) do
    Enum.find_value([3, 2, 1], fn size ->
      if byte_size(digits) > size do
        code = binary_part(digits, 0, size)
        if country = Map.get(@calling_codes, code), do: {code, country}
      end
    end)
  end

  @doc "The country of an E.164 number (`\"GR\"`), or nil when not one Palee knows."
  def country("+" <> digits) do
    case known_country(digits) do
      {_code, country} -> country
      nil -> nil
    end
  end

  def country(_phone), do: nil

  @doc "The number as staff lists show it: country code and the last 3 digits."
  def mask("+" <> digits) do
    {head, rest} = String.split_at(digits, min(2, byte_size(digits)))
    tail = String.slice(rest, -3, 3)
    hidden = String.duplicate("•", max(String.length(rest) - String.length(tail), 0))
    "+" <> head <> " " <> hidden <> tail
  end

  def mask(_other), do: "•••"
end
