defmodule Palee.Repo.Migrations.ProgrammePurchaseDays do
  @moduledoc """
  ADR-540: a bought programme is a sequence of days the buyer can catch up
  on («Έμεινε πίσω»: «Κάν' τη σήμερα» or «Παράλειψη»).

    * `day_dates`: the days the buyer moved (`"n" => "YYYY-MM-DD"`); the
      others fall on `starts_on + n` as before;
    * `skipped_days`: the days the buyer let go;
    * `planned_ends_on`: the end the purchase was sold with. `ends_on`
      follows the moved days (at most the programme's length later);
      refunds keep counting on the planned period. Purchases made before
      this have none: their `ends_on` is the planned end until a move sets
      it (no backfill under the tables' forced RLS).
  """

  use Ecto.Migration

  def up do
    alter table(:programme_purchases) do
      add :day_dates, :map, null: false, default: fragment("'{}'::jsonb")
      add :skipped_days, {:array, :integer}, null: false, default: []
      add :planned_ends_on, :date
    end

    create constraint(:programme_purchases, :programme_purchases_days_check,
             check: """
             jsonb_typeof(day_dates) = 'object'
             AND (planned_ends_on IS NULL
                  OR (planned_ends_on >= starts_on AND ends_on >= planned_ends_on))
             AND cardinality(skipped_days) <= 364
             """
           )
  end

  def down do
    drop constraint(:programme_purchases, :programme_purchases_days_check)

    alter table(:programme_purchases) do
      remove :day_dates
      remove :skipped_days
      remove :planned_ends_on
    end
  end
end
