defmodule Palee.Repo.Migrations.CommunityEventSmsSwitch do
  @moduledoc """
  ADR-385: the organiser's per-event SMS switch. On by default, so every
  existing event keeps sending its reminder and changes by SMS to those who
  asked at «Θα έρθω»; off sends them by push only.
  """

  use Ecto.Migration

  def change do
    alter table(:community_events) do
      add :sms_enabled, :boolean, null: false, default: true
    end
  end
end
