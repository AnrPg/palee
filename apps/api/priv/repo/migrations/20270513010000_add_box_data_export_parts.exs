defmodule Palee.Repo.Migrations.AddBoxDataExportParts do
  @moduledoc """
  ADR-367: the box's data export also carries its photos and PDFs.

  `parts` lists the extra ZIP files next to the CSV ZIP (`file`): each one
  holds stored files (documents and PDFs, logos, photos and videos) up to a
  size limit, so a large box gets several downloads instead of one huge one.
  Every part: `name`, `key`, `bytes`, `sha256`, `files` (how many files it
  holds). Tenant table: the existing RLS policy and tenant trigger cover it.
  """

  use Ecto.Migration

  def change do
    alter table(:box_data_exports) do
      add :parts, {:array, :map}, null: false, default: []
    end
  end
end
