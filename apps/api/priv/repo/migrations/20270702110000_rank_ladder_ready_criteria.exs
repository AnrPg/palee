defmodule Palee.Repo.Migrations.RankLadderReadyCriteria do
  @moduledoc """
  ADR-400 follow-up: per ladder, which requirements count for «Πληροί τις
  προϋποθέσεις» (`days`, `classes`, `skills`, at least one). Existing
  ladders keep what they counted before: days and classes.
  """

  use Ecto.Migration

  def change do
    alter table(:rank_ladders) do
      add :ready_criteria, {:array, :string}, null: false, default: ["classes", "days"]
    end

    create constraint(:rank_ladders, :rank_ladders_ready_criteria_check,
             check:
               "cardinality(ready_criteria) >= 1 AND ready_criteria <@ ARRAY['days', 'classes', 'skills']::varchar[]"
           )
  end
end
