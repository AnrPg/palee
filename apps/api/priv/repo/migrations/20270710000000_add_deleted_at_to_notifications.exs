defmodule Palee.Repo.Migrations.AddDeletedAtToNotifications do
  @moduledoc """
  ADR-460: a person can delete their own notifications. The row is kept
  (soft delete: `deleted_at` set) so the GDPR export still holds it, but no
  client ever lists, counts or marks it again. The live inbox reads only rows
  without `deleted_at`, newest first, so it gets its own partial index; the
  existing `(user_id, inserted_at)` index stays for reads over every row.
  """

  use Ecto.Migration

  def change do
    alter table(:notifications) do
      add :deleted_at, :utc_datetime_usec
    end

    create index(:notifications, [:user_id, "inserted_at DESC", "id DESC"],
             name: :notifications_live_inbox_index,
             where: "deleted_at IS NULL"
           )
  end
end
