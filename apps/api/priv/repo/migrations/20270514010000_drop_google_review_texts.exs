defmodule Palee.Repo.Migrations.DropGoogleReviewTexts do
  @moduledoc """
  ADR-387 amendment (product owner, 2026-11-03): until a lawyer has checked Google's
  terms, the box's Google listing shows only the rating and the number of
  reviews. Palee no longer reads, stores or returns the review texts and
  their authors (data minimisation), so the stored ones are erased with
  their column.
  """

  use Ecto.Migration

  def up do
    execute("ALTER TABLE google_place_snapshots DROP CONSTRAINT google_place_snapshots_check")

    alter table(:google_place_snapshots) do
      remove :reviews
    end

    create constraint(:google_place_snapshots, :google_place_snapshots_check,
             check: """
             status IN ('ok', 'not_found', 'failed')
             AND (rating IS NULL OR rating BETWEEN 1 AND 5)
             AND (rating_count IS NULL OR rating_count >= 0)
             AND attempts >= 0
             """
           )
  end

  def down do
    execute("ALTER TABLE google_place_snapshots DROP CONSTRAINT google_place_snapshots_check")

    alter table(:google_place_snapshots) do
      add :reviews, {:array, :map}, null: false, default: []
    end

    create constraint(:google_place_snapshots, :google_place_snapshots_check,
             check: """
             status IN ('ok', 'not_found', 'failed')
             AND (rating IS NULL OR rating BETWEEN 1 AND 5)
             AND (rating_count IS NULL OR rating_count >= 0)
             AND cardinality(reviews) <= 5
             AND attempts >= 0
             """
           )
  end
end
