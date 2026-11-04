defmodule Palee.Repo.Migrations.AddTrainsWithPaleeToUsers do
  @moduledoc """
  ADR-463: whether a profile also trains with Palee. Staff answer it once in
  the first run; NULL means never asked (members and athletes), which the
  apps read as "trains".
  """

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :trains_with_palee, :boolean
    end
  end
end
