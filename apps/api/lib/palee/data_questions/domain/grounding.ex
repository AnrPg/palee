defmodule Palee.DataQuestions.Domain.Grounding do
  @moduledoc """
  Checks that an answer only states numbers found in the data (ADR-361),
  pure. Every number written in the answer must equal, give or take
  rounding, a number of a result the answer cites, an argument, or a number
  in the question itself. Numbers are read in Greek and English styles
  (`1.234,50` and `1,234.50`), percent signs and currency symbols ignored.

  An answer with numbers the data does not hold is still shown, flagged
  `grounded: false` with the numbers listed, so the asker knows what to
  double-check; the audit log keeps the same flag.
  """

  @number ~r/(?<![\p{L}\d])\d{1,3}(?:[.,\x{00A0} ]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)?/u

  @doc "The numbers in the answer that no allowed value supports."
  def unsupported(answer, allowed) when is_binary(answer) do
    allowed = Enum.map(allowed, &(&1 * 1.0))

    answer
    |> strip_refs()
    |> then(&Regex.scan(@number, &1))
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.reject(fn token -> Enum.any?(readings(token), &supported?(&1, allowed)) end)
  end

  def unsupported(_answer, _allowed), do: []

  @doc "Numbers written in a text (the question), as values."
  def numbers_in(text) when is_binary(text) do
    @number |> Regex.scan(text) |> List.flatten() |> Enum.flat_map(&readings/1)
  end

  def numbers_in(_text), do: []

  # Citation markers ([q1]) and person refs (P3) are not figures.
  defp strip_refs(text), do: Regex.replace(~r/\[[^\]]{1,20}\]|\bP\d+\b|\bq\d+\b/u, text, "")

  defp readings(token) do
    plain = String.replace(token, ~r/[\x{00A0} ]/u, "")

    [
      plain |> String.replace(".", "") |> String.replace(",", "."),
      plain |> String.replace(",", ""),
      plain |> String.replace(",", ".")
    ]
    |> Enum.uniq()
    |> Enum.flat_map(fn candidate ->
      case Float.parse(candidate) do
        {value, ""} -> [value]
        _other -> []
      end
    end)
  end

  defp supported?(value, allowed) do
    Enum.any?(allowed, fn known ->
      known == value or abs(known - value) <= 0.5 or
        (known != 0 and abs(known - value) / abs(known) <= 0.005)
    end)
  end
end
