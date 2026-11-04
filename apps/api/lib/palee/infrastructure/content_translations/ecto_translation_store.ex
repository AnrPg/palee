defmodule Palee.Infrastructure.ContentTranslations.EctoTranslationStore do
  @moduledoc "Ecto adapter of the translations store (ADR-520)."

  @behaviour Palee.ContentTranslations.Ports.TranslationStore

  import Ecto.Query

  alias Palee.ContentTranslations.ContentTranslation
  alias Palee.Repo

  @fields [
    :subject_kind,
    :subject_id,
    :field,
    :locale,
    :text,
    :source_hash,
    :origin,
    :reviewed_at,
    :updated_by_id,
    :updated_at
  ]

  @impl true
  def list(%{organization_id: organization_id}, locale) do
    ContentTranslation
    |> where([t], t.organization_id == ^organization_id and t.locale == ^locale)
    |> select([t], map(t, ^@fields))
    |> Repo.all()
  end

  @impl true
  def list_many(%{organization_id: organization_id}, locales) do
    ContentTranslation
    |> where([t], t.organization_id == ^organization_id and t.locale in ^locales)
    |> select([t], map(t, ^@fields))
    |> Repo.all()
  end

  @impl true
  def put_many(%{organization_id: organization_id}, locale, rows) do
    now = DateTime.utc_now()

    entries =
      Enum.map(rows, fn row ->
        row
        |> Map.take([
          :subject_kind,
          :subject_id,
          :field,
          :text,
          :source_hash,
          :origin,
          :reviewed_at,
          :updated_by_id
        ])
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          locale: locale,
          inserted_at: now,
          updated_at: now
        })
      end)

    {_count, written} =
      Repo.insert_all(ContentTranslation, entries,
        on_conflict:
          {:replace, [:text, :source_hash, :origin, :reviewed_at, :updated_by_id, :updated_at]},
        conflict_target: [:organization_id, :locale, :subject_kind, :subject_id, :field],
        returning: @fields
      )

    {:ok, Enum.map(written, &Map.take(&1, @fields))}
  rescue
    error in Postgrex.Error -> {:error, error}
  end

  @impl true
  def delete_many(_context, _locale, []), do: 0

  def delete_many(%{organization_id: organization_id}, locale, keys) do
    condition =
      Enum.reduce(keys, dynamic(false), fn {kind, id, field}, acc ->
        dynamic(
          [t],
          ^acc or (t.subject_kind == ^kind and t.subject_id == ^id and t.field == ^field)
        )
      end)

    {count, _rows} =
      ContentTranslation
      |> where([t], t.organization_id == ^organization_id and t.locale == ^locale)
      |> where(^condition)
      |> Repo.delete_all()

    count
  end
end
