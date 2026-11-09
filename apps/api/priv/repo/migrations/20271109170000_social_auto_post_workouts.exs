defmodule Palee.Repo.Migrations.SocialAutoPostWorkouts do
  @moduledoc """
  ADR-565: «Ανέβαζε αυτόματα κάθε WOD στο Palee». `auto_post_workouts` is
  null until the person answers the one-time question after a finished
  WOD; then true or false, changeable in Κοινοποίηση & ορατότητα. The row
  keeps its existing security (only the person reads and writes their own).
  """

  use Ecto.Migration

  def change do
    alter table(:community_social_settings) do
      add :auto_post_workouts, :boolean, null: true
    end
  end
end
