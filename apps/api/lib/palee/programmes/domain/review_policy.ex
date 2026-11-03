defmodule Palee.Programmes.Domain.ReviewPolicy do
  @moduledoc """
  Reviews of a programme (ADR-370), pure.

    * Only a buyer reviews, once per purchase, after the programme started
      (an active or completed purchase whose start date has come).
    * 1 to 5 stars and an optional text of up to 1000 characters, editable
      by its author.
    * The seller never edits or deletes a review: they may hide it with a
      reason (abuse, personal data, off topic), which keeps it out of the
      averages and public lists; the author still sees it, marked hidden.
  """

  @max_body 1_000
  @hide_reasons ~w(abuse personal_data off_topic spam)

  def max_body, do: @max_body
  def hide_reasons, do: @hide_reasons

  @doc "Whether the buyer may review the purchase at `today`."
  def may_review(%{status: status, starts_on: starts_on}, %Date{} = today)
      when status in ["active", "completed"] do
    if Date.compare(today, starts_on) == :lt,
      do: {:error, :review_too_early},
      else: :ok
  end

  def may_review(_purchase, _today), do: {:error, :review_not_allowed}

  @doc "Normalised review fields or `{:error, :invalid_review}`."
  def normalize(params) do
    rating = params["rating"] || params[:rating]
    body = params["body"] || params[:body]
    body = if is_binary(body), do: String.trim(body), else: nil

    cond do
      not (is_integer(rating) and rating in 1..5) -> {:error, :invalid_review}
      is_binary(body) and String.length(body) > @max_body -> {:error, :invalid_review}
      true -> {:ok, %{rating: rating, body: if(body in [nil, ""], do: nil, else: body)}}
    end
  end

  @doc "A hide reason or `{:error, :invalid_hide_reason}`."
  def hide_reason(reason) when reason in @hide_reasons, do: {:ok, reason}
  def hide_reason(_reason), do: {:error, :invalid_hide_reason}

  @doc "Average and count of published reviews."
  def summary(reviews) do
    published = Enum.filter(reviews, &(&1.status == "published"))

    case published do
      [] ->
        %{average: nil, count: 0}

      list ->
        %{
          average: Float.round(Enum.sum(Enum.map(list, & &1.rating)) / length(list), 1),
          count: length(list)
        }
    end
  end
end
