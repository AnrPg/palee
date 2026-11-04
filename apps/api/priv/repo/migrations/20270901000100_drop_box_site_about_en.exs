defmodule Palee.Repo.Migrations.DropBoxSiteAboutEn do
  @moduledoc """
  ADR-500: the English «Σχετικά» lives in `content_translations` since the
  previous migration; the ADR-388 column goes. Rolling back re-adds it and the
  previous migration's `down` fills it again.
  """

  use Ecto.Migration

  def up do
    drop constraint(:box_site_settings, :box_site_settings_about_en_check)

    alter table(:box_site_settings) do
      remove :about_en
    end
  end

  def down do
    alter table(:box_site_settings) do
      add :about_en, :text
    end

    create constraint(:box_site_settings, :box_site_settings_about_en_check,
             check: "about_en IS NULL OR char_length(about_en) <= 4000"
           )
  end
end
