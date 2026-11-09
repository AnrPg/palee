defmodule Palee.Repo.Migrations.FeaturedPackage do
  @moduledoc """
  ADR-596: the box picks one «Προτεινόμενο» package for its public page and
  website. One per box by construction: it lives on the box's finance
  settings row. Deleting the package clears the choice.
  """

  use Ecto.Migration

  def change do
    alter table(:finance_settings) do
      add :featured_package_id,
          references(:membership_packages, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:finance_settings, [:featured_package_id])
  end
end
