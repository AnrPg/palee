defmodule Palee.Leads.LeadEvent do
  @moduledoc """
  ADR-344: one line of a lead's history. Kinds:

    * `created` - `%{source, campaign}` and, for forms, what was asked;
    * `enquired_again` - the same person asked again (`%{source}`);
    * `stage_changed` - `%{from, to, lost_reason}`;
    * `owner_changed` - `%{from, to}`;
    * `note` - `%{text}`;
    * `contacted` - `%{channel}` (staff called or wrote);
    * `task_added`, `task_done` - `%{task_id, title}`;
    * `message_sent` - an automation reached them (`%{recipe, channel}`);
    * `converted` - `%{user_id, via}`;
    * `marketing_opted_out` - they asked for no more marketing messages.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w(created enquired_again stage_changed owner_changed note contacted task_added
            task_done message_sent converted marketing_opted_out details_changed)

  @type t :: %__MODULE__{}

  schema "lead_events" do
    field :organization_id, :binary_id, read_after_writes: true
    field :lead_id, :binary_id
    field :kind, :string
    field :data, :map, default: %{}
    field :actor_id, :binary_id
    field :at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def kinds, do: @kinds

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [:lead_id, :kind, :data, :actor_id, :at])
    |> validate_required([:lead_id, :kind, :at])
    |> validate_inclusion(:kind, @kinds)
  end
end
