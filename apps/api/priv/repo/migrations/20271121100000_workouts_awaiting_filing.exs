defmodule Palee.Repo.Migrations.WorkoutsAwaitingFiling do
  @moduledoc """
  ADR-680: a WOD made for one thing (a day, a class, an athlete, a member)
  lives only in that thing's library folder.

    * `master_workouts.awaiting_filing`: the WOD was created from «+ Νέο WOD»
      inside a day, class, athlete or member screen. The first time it is
      filed for that purpose it is *moved* into the purpose's folder (and the
      flag cleared) instead of leaving the original at the library root with
      a copy in the folder. Every later filing copies, as for any template.
  """

  use Ecto.Migration

  def change do
    alter table(:master_workouts) do
      add :awaiting_filing, :boolean, null: false, default: false
    end
  end
end
