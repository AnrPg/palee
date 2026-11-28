defmodule Palee.Repo.Migrations.PackageRemovalReplacement do
  @moduledoc """
  ADR-660 addendum (2026-11-28): «Αλλαγή πακέτου» ends the package the
  member holds and starts the new one in the same step. The removal row
  keeps the package that took its place, so the history and the member's
  notification say «changed to», and undo takes the new package back.
  """

  use Ecto.Migration

  def change do
    alter table(:finance_package_removals) do
      add :replacement_subscription_id,
          references(:membership_package_subscriptions,
            type: :binary_id,
            on_delete: :nilify_all
          )

      add :replacement_package_name, :string
    end
  end
end
