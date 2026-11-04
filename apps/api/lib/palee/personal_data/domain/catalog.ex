defmodule Palee.PersonalData.Domain.Catalog do
  @moduledoc """
  ADR-267: where one person's own data lives, for "Download my data" (GDPR
  articles 15 and 20). Pure data, read by the record source adapter.

  Each entry names a table, the file of the archive it goes to (`section`),
  how its rows are found for the person (`subject`) and the session it is
  read in (`scope`):

    * `:account` – tables whose row-level security admits the owning
      profile itself (`app.user_id`), read once in the person's own session;
    * `:tenant` – a business's tables, read once per business the person
      belongs to, in that business's session with the person as the acting
      profile, exactly as the person's own requests read them. Row-level
      security still applies: nothing outside that business is visible.

  `subject` grammar:

    * `{:eq, column}` – the row's column holds the person's profile id;
    * `{:in, column, parent_table, parent_column, parent_subject}` – the
      row's column is one of `parent_column` of the parent rows that are the
      person's (by `parent_subject`, recursively);
    * `{:any, [subject]}` – any of them.

  A catalog is the one place that names other contexts' tables, as the
  tenancy audit does; a test checks every table and column against the
  database so it cannot drift silently.

  What never leaves (`strip/2`):

    * credentials and secrets: any column whose name says password, secret,
      token, PKCE, OAuth state, push keys or idempotency key, plus each
      entry's own `drop` list (provider keys are never exported, ADR-246);
    * other people: who on the staff acted (`*_by_id`) and the other party
      of a conversation, follow or block (each entry's `drop`).
  """

  @secret_column ~r/(password|secret|token|pkce|oauth_state|p256dh|auth_key|idempotency|api_key|private_key|credential)/
  @staff_column ~r/_by_id$/

  @me {:eq, "user_id"}

  defp memberships, do: {:in, "membership_id", "memberships", "id", @me}

  defp channel_contacts, do: {:in, "contact_id", "channel_contacts", "id", @me}

  defp fiscal_documents do
    {:any,
     [
       # ADR-262: the receipt of an online payment.
       {:in, "id", "payment_intents", "fiscal_document_id", @me},
       # The receipt of an invoice or of a payment recorded at the desk.
       {:in, "source_id", "finance_invoices", "id", @me},
       {:in, "source_id", "membership_payments", "id", memberships()}
     ]}
  end

  @doc "The archive's files, in order, each with what it holds."
  def sections do
    ~w(profile bookings training wellness devices messages community payments fiscal_documents signatures)
  end

  @doc "Every entry, in archive order."
  def entries do
    [
      # -- profile: the account, settings and memberships -----------------------
      account("profile", "users", {:eq, "id"},
        drop: ~w(search_text security_version calendar_feed_token_version)
      ),
      account("profile", "logins", {:in, "id", "users", "login_id", {:eq, "id"}},
        drop: ~w(security_version)
      ),
      account(
        "profile",
        "login_devices",
        {:in, "login_id", "users", "login_id", {:eq, "id"}},
        drop: ~w(device_hash)
      ),
      account("profile", "organization_memberships", @me, drop: ~w(invited_by_user_id)),
      account("profile", "account_interests", @me),
      account("profile", "community_social_settings", @me),
      account("profile", "notification_preferences", @me),
      account("profile", "saved_filters", @me),
      account("profile", "user_home_areas", @me),
      account("profile", "guide_progress", @me),
      account("profile", "journal_visibility_defaults", @me),
      account("profile", "user_gamification_preferences", @me),
      account("profile", "buddy_settings", @me),
      account("profile", "media_account_objects", @me),
      account("profile", "notifications", @me),
      # ADR-380: the yes or no to each box's marketing email, and the list
      # the box's email list was told.
      tenant("profile", "integration_marketing_consents", @me),
      tenant("profile", "audience_members", @me, drop: ~w(email_hash)),

      # -- bookings and visits ---------------------------------------------------
      tenant("bookings", "bookings", @me, drop: ~w(timeout_job_id)),
      tenant("bookings", "appointment_bookings", @me),
      tenant("bookings", "class_attendance_records", @me),
      tenant("bookings", "facility_check_ins", @me),
      tenant("bookings", "season_enrollments", @me),
      tenant("bookings", "scheduling_trial_requests", @me),
      tenant("bookings", "community_event_attendees", @me),
      # ADR-381: the doors the person opened or was refused at.
      tenant("bookings", "access_events", @me, drop: ~w(actor_id)),

      # -- training and journal --------------------------------------------------
      account("training", "journal_notes", @me),
      account("training", "journal_comments", @me),
      account("training", "goal_feedback", @me),
      account("training", "workout_executions", @me),
      account("training", "training_log_entries", @me),
      account("training", "user_pr_records", @me),
      # ADR-461: the exercise names a person typed (their suggestions).
      account("training", "exercise_names", @me),
      account("training", "user_achievements", @me),
      account("training", "user_stats", @me),
      account("training", "training_goals", @me),
      # ADR-374/375: split marks and a watch's heart rate of each workout.
      account("training", "execution_splits", @me),
      account("training", "execution_heart_rate_batches", @me),
      # ADR-377: belts and levels the box awarded.
      tenant("training", "rank_awards", @me),
      tenant("training", "rank_skill_checks", @me),
      account("training", "injury_reports", @me),
      tenant("training", "nutrition_plans", @me),
      # ADR-356: the leaderboard opt-in with its division and birth year.
      tenant("training", "leaderboard_opt_ins", @me),
      # ADR-394: the answer about the Palee-wide benchmark board.
      account("training", "palee_leaderboard_consents", @me),
      # ADR-395: the fitness card's body weight, birth year and choice, and
      # what each box's coach chose it shows.
      account("training", "fitness_profile_settings", @me),
      tenant("training", "fitness_display_overrides", {:eq, "client_user_id"}),
      tenant("training", "reviews", @me),

      # -- wellness and body -----------------------------------------------------
      account("wellness", "wellness_entries", @me),
      account("wellness", "craving_entries", @me),
      account("wellness", "wellbeing_check_ins", @me),
      account("wellness", "wellbeing_check_in_answers", @me),
      account("wellness", "body_settings", @me),
      account("wellness", "body_snapshots", @me),
      account("wellness", "body_snapshot_photos", @me),
      account("wellness", "wellness_preferences", @me),
      account("wellness", "user_health_consents", @me),
      account("wellness", "wellness_summary_grants", @me),
      account("wellness", "daily_stats", @me),
      # ADR-376: the person's own foods.
      account("wellness", "custom_foods", @me),

      # -- devices ---------------------------------------------------------------
      account("devices", "device_connections", @me, drop: ~w(provider_user_id)),
      account("devices", "device_activities", @me),
      account("devices", "device_imports", @me),
      # ADR-375: paired watches.
      account("devices", "watch_links", @me),
      # ADR-375 amendment: whether the watch was offered for each workout.
      account("devices", "watch_offers", @me),
      account("devices", "native_push_tokens", @me),
      account("devices", "push_subscriptions", @me, drop: ~w(endpoint)),

      # -- messages the person wrote ---------------------------------------------
      account("messages", "person_messages", {:eq, "author_id"}, drop: ~w(user_a_id user_b_id)),
      account("messages", "buddy_messages", {:eq, "author_id"}, drop: ~w(user_id buddy_user_id)),
      account("messages", "support_requests", @me),
      account("messages", "support_replies", @me, drop: ~w(buddy_user_id)),
      tenant("messages", "messaging_messages", {:eq, "sender_id"}),
      # ADR-344..347: how the person came to the box (their lead and its
      # history), the box's automatic messages to them and their choices
      # about them, and the box's latest «Σε κίνδυνο» score with its reasons.
      tenant("messages", "leads", @me, drop: ~w(owner_id)),
      tenant("messages", "lead_events", {:in, "lead_id", "leads", "id", @me}, drop: ~w(actor_id)),
      tenant("messages", "automation_deliveries", @me),
      tenant("messages", "automation_member_preferences", @me),
      tenant("messages", "retention_risks", @me),
      # ADR-384: what the box's staff did about it (who is left out).
      tenant("messages", "retention_risk_actions", @me, drop: ~w(actor_id)),
      tenant("messages", "communication_messages", {:eq, "sender_id"},
        drop: ~w(recipient_id recipient_role_snapshot)
      ),
      # ADR-280: Partners rows are the person's own (account-level).
      account("messages", "partner_messages", {:eq, "author_id"}),

      # ADR-348..350: the person's number, consents and the SMS the box sent them.
      tenant("messages", "channel_contacts", @me, drop: ~w(lead_id)),
      tenant("messages", "channel_consents", channel_contacts()),
      tenant("messages", "channel_messages", channel_contacts(),
        drop: ~w(idempotency_key provider_message_id claimed_at source_ref)
      ),

      # -- community -------------------------------------------------------------
      account("community", "community_profile_posts", @me),
      account("community", "community_profile_post_comments", @me),
      account("community", "community_profile_post_reactions", @me),
      account("community", "community_follows", @me),
      account("community", "community_user_blocks", @me, drop: ~w(blocked_user_id)),
      account("community", "partner_profiles", @me),
      account("community", "partner_swipes", {:eq, "swiper_id"}, drop: ~w(target_id)),
      account(
        "community",
        "partner_matches",
        {:any, [{:eq, "user_a_id"}, {:eq, "user_b_id"}]},
        drop: ~w(user_a_id user_b_id)
      ),
      account("community", "partner_reports", {:eq, "reporter_id"}, drop: ~w(target_id)),
      tenant("community", "community_posts", {:eq, "author_id"}),
      tenant("community", "community_post_comments", {:eq, "author_id"}),
      tenant("community", "community_post_reactions", @me),
      # ADR-355: Google review asks shown to the person and their opt-out.
      tenant("community", "review_asks", @me),
      tenant("community", "review_ask_opt_outs", @me),
      # ADR-386: the person's in-app reviews of a box, with the box's reply
      # (not who on staff wrote it).
      tenant("community", "box_reviews", @me, drop: ~w(replied_by_id)),
      # ADR-397: the reviews the person reported (not whose review, nor its
      # text), and the Palee team's decisions on their own reviews with the
      # statement of reasons (not who decided).
      tenant("community", "box_review_reports", {:eq, "reporter_id"},
        drop: ~w(review_author_id review_rating review_body decision_id)
      ),
      tenant("community", "box_review_decisions", {:eq, "review_author_id"}),
      # ADR-280 verification: the outcome and the person's own request; the
      # phone and selfie never leave, nor who else is named.
      account("community", "partner_verifications", @me, drop: ~w(source_organization_id)),
      account("community", "partner_verification_requests", @me,
        drop: ~w(phone_ciphertext phone_hash selfie_key)
      ),
      account("community", "partner_sponsorships", {:eq, "candidate_id"}, drop: ~w(sponsor_id)),

      # -- payments, packages and invoices ---------------------------------------
      tenant("payments", "memberships", @me, drop: ~w(referred_by_user_id)),
      tenant("payments", "membership_payments", memberships()),
      tenant("payments", "finance_invoices", @me),
      tenant(
        "payments",
        "finance_invoice_lines",
        {:in, "finance_invoice_id", "finance_invoices", "id", @me}
      ),
      tenant("payments", "finance_credit_ledger_entries", @me),
      tenant("payments", "finance_payment_reversals", @me),
      tenant("payments", "finance_refund_receipts", @me),
      # ADR-291: packages the person asked to pay for at the desk.
      tenant("payments", "finance_package_requests", @me),
      # ADR-450: the contact a box keeps while a deleted profile still owes it.
      tenant("payments", "finance_debtor_contacts", @me),
      tenant("payments", "payment_intents", @me,
        drop: ~w(redirect_url return_url provider_ref claimed_at)
      ),
      tenant("payments", "payment_methods", @me),
      tenant("payments", "shop_orders", @me),
      tenant("payments", "perk_claims", @me),
      # ADR-371: programmes bought, the WODs they scheduled and their reviews.
      tenant("payments", "programme_purchases", @me),
      tenant("training", "programme_deliveries", @me),
      tenant("training", "programme_reviews", @me),
      tenant("payments", "wallet_passes", @me, drop: ~w(serial)),
      # ADR-341: a coach's own pay rules and statements (the sources of
      # commission lines are other people's payments: left out).
      tenant("payments", "coach_pay_rules", {:eq, "coach_user_id"}),
      tenant("payments", "coach_pay_statements", {:eq, "coach_user_id"}),
      tenant(
        "payments",
        "coach_pay_lines",
        {:in, "statement_id", "coach_pay_statements", "id", {:eq, "coach_user_id"}},
        drop: ~w(source_id)
      ),

      # -- fiscal documents addressed to the person ------------------------------
      tenant("fiscal_documents", "fiscal_documents", fiscal_documents(),
        drop: ~w(request_hash journal_position)
      ),
      tenant(
        "fiscal_documents",
        "fiscal_document_lines",
        {:in, "document_id", "fiscal_documents", "id", fiscal_documents()}
      ),

      # -- documents signed, and health certificates -----------------------------
      tenant("signatures", "document_signatures", @me, drop: ~w(evidence_object_key)),
      tenant("signatures", "document_signature_requests", @me),
      tenant("signatures", "health_certificates", @me, drop: ~w(file_key)),
      # ADR-377 addendum: a coach's diploma signature and its trail (the
      # images themselves go in the archive's `files/`).
      account("signatures", "diploma_signatures", @me, drop: ~w(object_key)),
      account("signatures", "diploma_signature_events", @me)
    ]
  end

  @doc "The entries of one scope."
  def entries(scope) when scope in [:account, :tenant],
    do: Enum.filter(entries(), &(&1.scope == scope))

  @doc "Every table a subject reads, the entry's own first."
  def tables(%{table: table, subject: subject}), do: Enum.uniq([table | subject_tables(subject)])

  defp subject_tables({:eq, _column}), do: []

  defp subject_tables({:in, _column, parent, _parent_column, parent_subject}),
    do: [parent | subject_tables(parent_subject)]

  defp subject_tables({:any, subjects}), do: Enum.flat_map(subjects, &subject_tables/1)

  @doc "Columns a row of `entry` never leaves with (see the moduledoc)."
  def dropped?(entry, column) when is_binary(column) do
    column in entry.drop or Regex.match?(@secret_column, column) or
      Regex.match?(@staff_column, column)
  end

  @doc "A row as it leaves: secrets, staff and other people's columns removed."
  def strip(entry, row) when is_map(row),
    do: row |> Enum.reject(fn {column, _value} -> dropped?(entry, column) end) |> Map.new()

  defp account(section, table, subject, opts \\ []),
    do: entry(:account, section, table, subject, opts)

  defp tenant(section, table, subject, opts \\ []),
    do: entry(:tenant, section, table, subject, opts)

  defp entry(scope, section, table, subject, opts) do
    %{
      scope: scope,
      section: section,
      table: table,
      subject: subject,
      drop: Keyword.get(opts, :drop, [])
    }
  end
end
