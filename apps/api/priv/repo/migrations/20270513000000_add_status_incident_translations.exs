defmodule Palee.Repo.Migrations.AddStatusIncidentTranslations do
  @moduledoc """
  ADR-366: the Palee team writes incidents in any language and the page also
  shows them in English.

    * `status_incidents.locale` and `status_incident_updates.locale` – the
      language the title and note were written in (detected), or NULL when
      unknown.
    * `title_en` / `body_en` – the English version, NULL when the text is
      already English or the translation failed (the page then shows the
      original).
    * `en_source` – `auto` (machine translation, shown as such) or `edited`
      (checked or corrected by the person who published it).

  Platform data (no tenant): the existing read/write policies of ADR-364
  cover the new columns.
  """

  use Ecto.Migration

  def change do
    for table <- [:status_incidents, :status_incident_updates] do
      alter table(table) do
        add :locale, :text
        add :en_source, :text
      end
    end

    alter table(:status_incidents) do
      add :title_en, :text
    end

    alter table(:status_incident_updates) do
      add :body_en, :text
    end

    create constraint(:status_incidents, :status_incidents_translation_check,
             check:
               "(locale IS NULL OR char_length(locale) BETWEEN 2 AND 8) " <>
                 "AND (en_source IS NULL OR en_source IN ('auto', 'edited')) " <>
                 "AND (title_en IS NULL OR char_length(title_en) BETWEEN 3 AND 140) " <>
                 "AND ((title_en IS NULL) = (en_source IS NULL))"
           )

    create constraint(:status_incident_updates, :status_incident_updates_translation_check,
             check:
               "(locale IS NULL OR char_length(locale) BETWEEN 2 AND 8) " <>
                 "AND (en_source IS NULL OR en_source IN ('auto', 'edited')) " <>
                 "AND (body_en IS NULL OR char_length(body_en) BETWEEN 1 AND 2000) " <>
                 "AND ((body_en IS NULL) = (en_source IS NULL))"
           )
  end
end
