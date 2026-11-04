defmodule Palee.Repo.Migrations.BoxSiteTemplates do
  @moduledoc """
  ADR-530: box website templates, palettes and publishing.

    * `box_site_settings` gets `template`, `palette`, `appearance`,
      `calm_motion`, `draft` (what waits for «Δημοσίευση»), `published_at`,
      `template_notice` (the in-app notice of a site the migration moved) and
      `template_notice_sent_at` (the one-off notification to the box's staff);
    * new rows default to template `tiles` with the timetable on;
    * every existing site moves to template `arena` with the Palee palette and
      gets the notice: the rows that exist, and a row for every box that
      published its public page without ever saving website settings (its
      timetable stays off, as it was);
    * `palee_box_site_template_notices_due()` lists the live boxes whose notice
      was not sent yet (never a demo business), for `BoxSiteJob`;
    * `palee_box_pr_count(org, from, to)` counts the PRs recorded in a box
      between two dates (the site's «Αριθμοί κοινότητας»): one aggregate,
      never a person;
    * notification type `site_template_changed`.

  The functions are SECURITY DEFINER and pin only `search_path`.
  """

  use Ecto.Migration

  @templates ~w(arena tiles stories atelier)
  @palettes ~w(palee electric flame sun amber emerald aegean violet fuchsia olive navy mono)
  @appearances ~w(auto light dark)
  @notification_types ~w(site_template_changed)

  def up do
    alter table(:box_site_settings) do
      add :template, :text, null: false, default: "tiles"
      add :palette, :text, null: false, default: "palee"
      add :appearance, :text, null: false, default: "auto"
      add :calm_motion, :boolean, null: false, default: false
      add :draft, :map
      add :published_at, :utc_datetime_usec
      add :template_notice, :boolean, null: false, default: false
      add :template_notice_sent_at, :utc_datetime_usec
    end

    create constraint(:box_site_settings, :box_site_settings_look_check,
             check: """
             template IN (#{quoted(@templates)})
             AND palette IN (#{quoted(@palettes)})
             AND appearance IN (#{quoted(@appearances)})
             AND (draft IS NULL OR jsonb_typeof(draft) = 'object')
             """
           )

    flush()

    # Existing sites keep their look's family: «Αρένα», with a notice.
    execute("UPDATE box_site_settings SET template = 'arena', template_notice = true")

    execute("""
    INSERT INTO box_site_settings
      (id, organization_id, public_schedule, template, template_notice, inserted_at, updated_at)
    SELECT gen_random_uuid(), p.organization_id, false, 'arena', true, now(), now()
    FROM organization_public_profiles p
    WHERE p.published_at IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM box_site_settings s WHERE s.organization_id = p.organization_id
      )
    """)

    # ADR-530: for new boxes the timetable is on by default.
    alter table(:box_site_settings) do
      modify :public_schedule, :boolean,
        null: false,
        default: true,
        from: {:boolean, default: false}
    end

    execute("""
    CREATE FUNCTION palee_box_site_template_notices_due()
    RETURNS TABLE (organization_id uuid)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT s.organization_id FROM public.box_site_settings s
      JOIN public.organizations o ON o.id = s.organization_id
      WHERE s.template_notice AND s.template_notice_sent_at IS NULL
        AND o.status = 'active' AND o.activation <> 'demo'
      LIMIT 200
    $$
    """)

    execute("""
    CREATE FUNCTION palee_box_pr_count(org_id uuid, from_date date, to_date date)
    RETURNS bigint
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT
        (SELECT count(*) FROM public.user_pr_records r
         WHERE r.organization_id = org_id AND r.beaten_on BETWEEN from_date AND to_date)
        +
        (SELECT count(*) FROM public.user_pr_history h
         JOIN public.user_pr_records r ON r.id = h.pr_record_id
         WHERE r.organization_id = org_id AND h.beaten_on BETWEEN from_date AND to_date)
    $$
    """)

    rewrite_notification_types(&Enum.uniq(&1 ++ @notification_types))
  end

  # The constraint is rewritten from what the database holds, so types other
  # migrations add are kept (as in ADR-393's migration).
  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN ('site_template_changed')")
    rewrite_notification_types(&(&1 -- @notification_types))
    execute("DROP FUNCTION IF EXISTS palee_box_pr_count(uuid, date, date)")
    execute("DROP FUNCTION IF EXISTS palee_box_site_template_notices_due()")

    alter table(:box_site_settings) do
      modify :public_schedule, :boolean,
        null: false,
        default: false,
        from: {:boolean, default: true}
    end

    drop constraint(:box_site_settings, :box_site_settings_look_check)

    alter table(:box_site_settings) do
      remove :template_notice_sent_at
      remove :template_notice
      remove :published_at
      remove :draft
      remove :calm_motion
      remove :appearance
      remove :palette
      remove :template
    end
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
