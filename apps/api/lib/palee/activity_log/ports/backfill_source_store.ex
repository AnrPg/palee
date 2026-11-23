defmodule Palee.ActivityLog.Ports.BackfillSourceStore do
  @moduledoc """
  ADR-760 (11A): the older records the «Αρχείο ενεργειών» starts from. Each
  source is one kind of past change kept in another context's table (a
  freeze, a refund, a declined trial...). Calls run in one box's session
  (`app.organization_id`) and read only that box's rows.
  """

  @typedoc """
  One past change, the same shape for every source:

    * `ref`: names the row it came from (`"<table>:<id>"`, plus a suffix
      when one row holds two changes), so copying twice adds nothing.
    * `id`: the source row's id, the cursor of the next page.
    * `kind`: what the source row says it was, when the source holds
      several kinds (a value override's field, a benefit's grant/revoke).
  """
  @type fact :: %{
          ref: String.t(),
          id: Ecto.UUID.t(),
          occurred_at: DateTime.t(),
          kind: String.t() | nil,
          actor_user_id: Ecto.UUID.t() | nil,
          actor_roles: [String.t()],
          person_user_id: Ecto.UUID.t() | nil,
          subject: map(),
          subject_label: String.t() | nil,
          reason: String.t() | nil,
          details: map()
        }

  @doc """
  Up to `limit` facts of `source` whose source rows come after the row
  `after_id` (`nil`: from the first), in the order of their ids.
  """
  @callback read(source :: atom(), after_id :: Ecto.UUID.t() | nil, limit :: pos_integer()) ::
              [fact()]
end
