defmodule Palee.Gamification.Queries.GetTrainingQuote do
  import Ecto.Query

  alias Palee.Gamification.TrainingQuote
  alias Palee.Repo

  def for_subject(%Date{} = date, subject_id, locale \\ nil) when is_binary(subject_id) do
    scope = scope_for(locale)
    count = Repo.aggregate(scope, :count)

    if count == 0 do
      nil
    else
      offset = :erlang.phash2({Date.to_iso8601(date), subject_id}, count)

      scope
      |> order_by([quote], asc: quote.id)
      |> offset(^offset)
      |> limit(1)
      |> Repo.one()
    end
  end

  # The member's language when it has quotes; otherwise every quote, so a
  # language without its own list still sees one.
  defp scope_for(locale) when locale in ["el", "en"] do
    scoped = from(q in TrainingQuote, where: q.locale == ^locale)
    if Repo.exists?(scoped), do: scoped, else: TrainingQuote
  end

  defp scope_for(_locale), do: TrainingQuote
end
