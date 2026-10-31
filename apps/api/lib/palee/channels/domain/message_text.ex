defmodule Palee.Channels.Domain.MessageText do
  @moduledoc """
  How long a text message is and how many parts it is billed as (ADR-348
  §6). A text that only uses the GSM 03.38 alphabet goes 160 characters in
  one SMS (153 per part when split); anything else, including lower-case
  Greek, is sent as UCS-2: 70 characters (67 per part). Viber and WhatsApp
  are billed per message, so they always count as one.
  """

  @max_length 1_000

  # GSM 03.38 basic set, plus the extension table (each takes two septets).
  @gsm_basic ~c"@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
  @gsm_extension ~c"^{}\\[~]|€\f"

  @gsm_basic_set MapSet.new(@gsm_basic)
  @gsm_extension_set MapSet.new(@gsm_extension)

  def max_length, do: @max_length

  @doc "`:gsm7` or `:ucs2`."
  def encoding(text) when is_binary(text) do
    if text |> String.to_charlist() |> Enum.all?(&gsm?/1), do: :gsm7, else: :ucs2
  end

  defp gsm?(char),
    do: MapSet.member?(@gsm_basic_set, char) or MapSet.member?(@gsm_extension_set, char)

  @doc "The number of billed parts of `text` on `channel`."
  def segments("sms", text) when is_binary(text) do
    case encoding(text) do
      :gsm7 -> parts(gsm_length(text), 160, 153)
      # UTF-16 code units: a character outside the BMP (an emoji) takes two.
      :ucs2 -> parts(utf16_length(text), 70, 67)
    end
  end

  def segments(_channel, _text), do: 1

  defp parts(length, single, _part) when length <= single, do: 1
  defp parts(length, _single, part), do: div(length + part - 1, part)

  defp gsm_length(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, sum ->
      if MapSet.member?(@gsm_extension_set, char), do: sum + 2, else: sum + 1
    end)
  end

  defp utf16_length(text),
    do: text |> :unicode.characters_to_binary(:utf8, :utf16) |> byte_size() |> div(2)
end
