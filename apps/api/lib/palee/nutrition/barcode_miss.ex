defmodule Palee.Nutrition.BarcodeMiss do
  @moduledoc """
  A barcode a scan found in no source (ADR-421), per country, counted:
  how many scans, the first and the last day. Never who scanned, the time
  of day or the box: only what the Palee team needs to see the gaps.
  """

  use Ecto.Schema

  @primary_key false

  @type t :: %__MODULE__{}

  schema "food_barcode_misses" do
    field(:barcode, :string, primary_key: true)
    field(:country, :string, primary_key: true)
    field(:scans, :integer)
    field(:first_seen_on, :date)
    field(:last_seen_on, :date)
  end
end
