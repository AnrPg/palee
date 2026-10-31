defmodule Palee.Status.DailySample do
  @moduledoc "ADR-364: how many probes of a component ran on a UTC day, by outcome."

  use Ecto.Schema

  @primary_key false

  @type t :: %__MODULE__{}

  schema "status_daily_samples" do
    field :component, :string, primary_key: true
    field :day, :date, primary_key: true
    field :total, :integer, default: 0
    field :operational, :integer, default: 0
    field :degraded, :integer, default: 0
    field :down, :integer, default: 0
  end
end
