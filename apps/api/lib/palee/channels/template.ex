defmodule Palee.Channels.Template do
  @moduledoc """
  A box's own wording of a channel message in one language (ADR-350 §2).
  Channel `whatsapp` rows carry the provider's template id and whether
  Meta approved it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "channel_templates" do
    field :organization_id, :binary_id, read_after_writes: true
    field :key, :string
    field :locale, :string
    field :channel, :string, default: "any"
    field :body, :string
    field :provider_template_id, :string
    field :variable_names, {:array, :string}, default: []
    field :approval_status, :string, default: "none"
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :key,
      :locale,
      :channel,
      :body,
      :provider_template_id,
      :variable_names,
      :approval_status,
      :updated_by_id
    ])
    |> validate_required([:key, :locale, :channel, :body])
    |> unique_constraint([:organization_id, :key, :locale, :channel])
    |> check_constraint(:channel, name: :channel_templates_check)
  end
end
