defmodule Palee.Repo.Migrations.StaffNoteAudience do
  @moduledoc """
  ADR-359 (CP-E5): who reads a note about a member. `private` is ADR-101's
  coach note (author, owners, admins with the author's consent); `staff`
  is an internal comment every staff member of the box reads, the front
  desk included («Σημείωση για το staff»). Existing notes stay private.
  """

  use Ecto.Migration

  def change do
    alter table(:coaching_notes) do
      add :audience, :string, size: 16, null: false, default: "private"
    end

    create constraint(:coaching_notes, :coaching_notes_audience_check,
             check: "audience IN ('private', 'staff')"
           )

    create index(:coaching_notes, [:organization_id, :client_user_id],
             where: "audience = 'staff'",
             name: :coaching_notes_staff_audience_index
           )
  end
end
