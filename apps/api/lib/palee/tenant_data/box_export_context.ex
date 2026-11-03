defmodule Palee.TenantData.BoxExportContext do
  @moduledoc """
  Tenant scope for the box's own data export (ADR-365, CP-G5).

  Built only by `Palee.BoxData.export_context/2` for an owner's pending
  export. `TableStore` accepts it for `inventory/2` and `export/3`, never
  for `purge/2`.

  * `organization_id` – the box; becomes `app.organization_id`.
  * `user_id` – the owner who asked; becomes `app.user_id`, so the export
    holds exactly what row-level security lets that owner read.
  * `subject_user_ids` – always empty: members' personal tables (journal,
    wellness, body, devices, their own logs; RLS keyed on the member) are
    theirs, not the box's, and each member downloads them from Settings
    (ADR-267).
  """

  @enforce_keys [:organization_id, :export_id, :user_id]
  defstruct [:organization_id, :export_id, :user_id, subject_user_ids: [], source: :box_export]

  @type t :: %__MODULE__{
          organization_id: Ecto.UUID.t(),
          export_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          subject_user_ids: [],
          source: :box_export
        }
end
