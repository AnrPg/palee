defmodule Palee.ReviewAsks.Domain.BoxReviewPolicy do
  @moduledoc """
  ADR-386: in-app reviews of a box (stars and text).

    * Only a person who checked in at the box at least once may review it,
      and once: a second write edits the first.
    * The author may edit or delete their review; the box may reply (and edit
      its reply) but never delete or hide a review.
    * Every review counts in the average, whatever its stars: nothing is
      filtered by opinion (the same rule as the asks of ADR-355).
    * Shown with the author's first name only (data minimisation), in the
      app and on the box's website.

  Pure: callers bring the facts and the time.
  """

  @max_body 2_000
  @max_reply 2_000
  @public_latest 6

  def max_body, do: @max_body
  def public_latest, do: @public_latest

  @doc "`:ok` when the person may write a review (they checked in at least once)."
  def may_review(%{attendance_count: count}) when is_integer(count) and count > 0, do: :ok
  def may_review(_facts), do: {:error, :review_needs_check_in}

  @doc """
  Validates a review (string keys): `{:ok, %{rating, body}}` or
  `{:error, {:invalid_fields, errors}}`. The text is optional.
  """
  def review(params) when is_map(params) do
    errors = %{}

    {rating, errors} =
      case Map.get(params, "rating") do
        value when is_integer(value) and value in 1..5 -> {value, errors}
        _other -> {nil, Map.put(errors, :rating, "invalid")}
      end

    {body, errors} =
      case text(Map.get(params, "body"), @max_body) do
        {:ok, body} -> {body, errors}
        :error -> {nil, Map.put(errors, :body, "too_long")}
      end

    if errors == %{},
      do: {:ok, %{rating: rating, body: body}},
      else: {:error, {:invalid_fields, errors}}
  end

  def review(_params), do: {:error, {:invalid_fields, %{rating: "invalid"}}}

  @doc "Validates the box's reply: `{:ok, text}` or `{:error, {:invalid_fields, _}}`."
  def reply(params) when is_map(params) do
    case text(Map.get(params, "body"), @max_reply) do
      {:ok, body} when is_binary(body) -> {:ok, body}
      _invalid -> {:error, {:invalid_fields, %{body: "invalid"}}}
    end
  end

  def reply(_params), do: {:error, {:invalid_fields, %{body: "invalid"}}}

  defp text(nil, _max), do: {:ok, nil}

  defp text(value, max) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> {:ok, nil}
      String.length(value) > max -> :error
      true -> {:ok, value}
    end
  end

  defp text(_value, _max), do: :error

  @doc "The average stars with one decimal, or nil without reviews."
  def average(%{count: 0}), do: nil
  def average(%{count: count, sum: sum}) when count > 0, do: Float.round(sum / count, 1)

  @doc "The name shown with a review: the first word of the person's name."
  def author_name(nil), do: nil

  def author_name(name) when is_binary(name) do
    case name |> String.trim() |> String.split(~r/\s+/, parts: 2) do
      [""] -> nil
      [first | _rest] -> String.slice(first, 0, 40)
    end
  end
end
