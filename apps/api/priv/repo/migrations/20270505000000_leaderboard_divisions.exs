defmodule Palee.Repo.Migrations.LeaderboardDivisions do
  @moduledoc """
  ADR-356 (CP-D2): what a person who opted in to a box's leaderboards tells
  it so they can be compared fairly: their division (`women`, `men`, or
  nothing) and their birth year (for age groups). Both are optional, set by
  the person only, and live on the opt-in row, so opting out deletes them.
  The birth year alone is kept (not the date): enough for masters-style age
  groups, which use the age reached during the year.
  """

  use Ecto.Migration

  def change do
    alter table(:leaderboard_opt_ins) do
      add :division, :string, size: 16
      add :birth_year, :integer
    end

    create constraint(:leaderboard_opt_ins, :leaderboard_opt_ins_division_check,
             check:
               "(division IS NULL OR division IN ('women', 'men')) AND " <>
                 "(birth_year IS NULL OR birth_year BETWEEN 1900 AND 2100)"
           )
  end
end
