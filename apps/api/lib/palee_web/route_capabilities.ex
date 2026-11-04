defmodule PaleeWeb.RouteCapabilities do
  @moduledoc """
  The capability each staff route needs (ADR-099). A request passes when the
  tenant context holds ANY of the listed capabilities; data scope (a coach's
  own clients, ADR-100) is enforced by the application services behind it.

  Every `/api/org/:slug/admin` and `/api/org/:slug/staff` route must be listed:
  `RouteCapabilitiesTest` fails on a route without an entry, so a new staff
  endpoint can never fall back to "any staff member".
  """

  alias PaleeWeb, as: W

  # ADR-382: what any staff role holds, for reading one's own pay.
  @own_pay [
    :run_classes,
    :manage_appointments,
    :check_in,
    :take_payments,
    :view_finance_reports,
    :record_cleaning
  ]

  @controller_defaults %{
    W.AdminWorkoutController => [:manage_workouts],
    # ADR-377: belts and levels; promotions follow the coaching scope (ADR-100).
    # ADR-400 follow-up: ladders are the owner's, admins' and head coaches'
    # (`RankLadders` refuses a coach with only their own clients).
    W.AdminRankLaddersController => [:manage_settings, :manage_coaching],
    W.StaffRanksController => [:manage_coaching],
    # ADR-252: templates, versions, requirement, settings and audit.
    W.AdminDocumentsController => [:manage_settings],
    W.AdminHealthCertificatesController => [:manage_health_certificates],
    # The class form's WOD picker: whoever schedules classes picks WODs.
    W.AdminWorkoutChoiceController => [:manage_schedule, :manage_workouts],
    # ADR-230: the day's WOD, like linking a WOD to one class.
    W.AdminDayWorkoutController => [:manage_schedule, :manage_workouts],
    # ADR-359: whoever runs classes or the desk sees who is new.
    W.AdminVisitBadgesController => [:run_classes, :check_in, :manage_schedule],
    W.AdminWorkoutDslController => [:manage_workouts],
    W.AdminWorkoutFolderController => [:manage_workouts],
    W.AdminWorkoutGoalsController => [:manage_workouts],
    W.AdminChallengeController => [:manage_challenges],
    W.AdminAssignedWorkoutController => [:manage_coaching],
    W.AdminContentController => [:manage_content],
    W.AdminCoachingController => [:view_client_training],
    W.AdminReviewController => [:view_feedback],
    W.AdminWellbeingController => [:view_health],
    W.AdminInjuryWarningController => [:view_health],
    W.AdminSearchController => [:view_directory],
    W.AdminAnalyticsController => [:view_business_analytics],
    W.AdminShopReportController => [:view_business_analytics, :manage_shop],
    W.CoachingExtrasController => [:manage_coaching],
    W.AppointmentsController => [:manage_appointments],
    W.StaffController => [:manage_coaching, :manage_appointments, :manage_schedule],
    W.PaymentModelsController => [:manage_billing],
    # ADR-348..351: the provider, budget and wording are settings; numbers,
    # consents and sending belong to whoever messages from the box.
    W.AdminChannelSettingsController => [:manage_settings],
    # ADR-368: the box's own SMTP email provider.
    W.AdminChannelEmailController => [:manage_settings],
    W.AdminChannelContactsController => [:message_from_box],
    W.AdminChannelMessagesController => [:message_from_box],
    W.AdminChannelClassNoticesController => [:message_from_box],
    W.CoachingRelationshipsController => [:assign_coaches, :manage_coaching],
    W.RoleAccessController => [:manage_settings],
    W.InventoryController => [:manage_inventory],
    W.ShopController => [:manage_shop],
    W.OwnerOrganizationController => [:manage_organization_lifecycle],
    # ADR-365: a copy of all the box's data is for owners.
    W.AdminDataExportController => [:manage_organization_lifecycle],
    W.AdminWorkoutTimerPreviewController => [:manage_workouts],
    W.AdminBrandingController => [:manage_settings],
    W.AdminPublicProfileController => [:manage_settings],
    # ADR-352..354: the website, its domains and tags.
    W.AdminSiteController => [:manage_settings],
    # ADR-355: Google review asks (settings and counts only).
    W.AdminReviewAsksController => [:manage_settings],
    # ADR-386: replying to reviews speaks as the box (like the box inbox).
    W.AdminBoxReviewsController => [:message_from_box],
    W.HomeLocationController => [:manage_memberships],
    W.AdminWorkoutFreeTextController => [:manage_workouts],
    W.AdminOnboardingController => [:manage_settings],
    # ADR-170: the platform plan card (owners and admins hold manage_settings).
    W.AdminPlanController => [:manage_settings],
    W.TrainingHistoryController => [:view_client_training],
    # ADR-174: the queue also requires view_health per athlete (service).
    W.StaffScalingController => [:manage_coaching],
    W.AdminAiSettingsController => [:manage_settings],
    # ADR-184: demo data and the activation request (owners and admins).
    W.AdminBusinessController => [:manage_settings],
    # ADR-255: settings catalog and setup recipes (applying is owner only, in the service).
    W.AdminSetupController => [:manage_settings],
    # ADR-191: partner perks.
    W.AdminPerkController => [:manage_perks],
    # ADR-253: box screens (TVs on the wall), their codes and overrides.
    W.AdminBoxScreenController => [:manage_settings, :manage_locations],
    # ADR-254: CSV imports (owners and admins hold manage_settings).
    W.AdminImportController => [:manage_settings],
    # ADR-344/345: «Ενδιαφερόμενοι».
    W.AdminLeadController => [:manage_leads],
    # ADR-346: the ready recipes (owners and admins).
    W.AdminAutomationController => [:manage_automations],
    # ADR-347: «Σε κίνδυνο».
    W.AdminMemberRiskController => [:view_members_at_risk]
  }

  @actions %{
    # People
    {W.AdminUserController, :index} => [:view_directory, :view_billing_contacts],
    {W.AdminUserController, :index_athletes} => [:view_directory],
    {W.AdminUserController, :show} => [:view_directory, :view_billing_contacts],
    {W.AdminUserController, :finance} => [:manage_billing, :take_payments],
    {W.AdminUserController, :training_history} => [:view_client_training],
    {W.AdminUserController, :schedule} => [:view_client_training, :run_classes],
    {W.AdminUserController, :program_workout} => [:manage_coaching],
    {W.AdminUserController, :program_workout_for_users} => [:manage_coaching],
    {W.AdminUserController, :place_in_class} => [:book_for_clients, :manage_schedule],
    {W.AdminUserController, :class_placement_options} => [:book_for_clients, :manage_schedule],
    {W.AdminUserController, :prs} => [:view_client_training],
    {W.AdminUserController, :pr_members} => [:view_client_training],
    {W.AdminUserController, :incidents} => [:view_health],
    {W.AdminUserController, :messages} => [:message_clients],
    {W.AdminUserController, :coaching_context} => [:view_client_training],
    {W.AdminUserController, :grant_allowance} => [:manage_billing],
    {W.AdminUserController, :revoke_allowance} => [:manage_billing],
    {W.AdminUserController, :freezes} => [:manage_billing, :take_payments],
    {W.AdminUserController, :create_freeze} => [:manage_billing],
    {W.AdminUserController, :cancel_freeze} => [:manage_billing],
    {W.AdminUserController, :delete} => [:manage_memberships],
    {W.AdminUserController, :update_role} => [:grant_staff_roles],
    {W.AdminUserController, :update_roles} => [:grant_staff_roles],
    {W.AdminUserController, :update_coach_scope} => [:set_head_coach],
    {W.StaffLocationScopeController, :update} => [:grant_staff_roles],
    {W.AdminUserController, :membership_status} => [:view_membership_status],

    # Gym settings and facility
    {W.AdminSettingsController, :show} => [:manage_settings, :manage_finance_settings],
    {W.AdminSettingsController, :update} => [:manage_settings],
    {W.AdminSettingsController, :update_time_zone} => [:manage_settings],
    # ADR-186: a branch-scoped manager edits only their branches (checked per
    # location); opening a new branch is a gym-wide decision.
    {W.AdminFacilityController, :index_locations} => [
      :manage_settings,
      :manage_locations,
      :manage_schedule,
      :check_in,
      :review_cleaning
    ],
    {W.AdminFacilityController, :create_location} => [:manage_settings],
    {W.AdminFacilityController, :update_location} => [:manage_settings, :manage_locations],
    {W.AdminFacilityController, :archive_location} => [:manage_settings],
    {W.AdminFacilityController, :search_addresses} => [:manage_settings, :manage_locations],
    {W.AdminFacilityController, :reverse_geocode} => [:manage_settings, :manage_locations],
    {W.AdminFacilityController, :resolve_map_link} => [:manage_settings, :manage_locations],
    {W.AdminFacilityController, :index_check_ins} => [:check_in],
    {W.AdminFacilityController, :create_check_in} => [:check_in],
    # ADR-155: QR check-in desk, door display and rules.
    {W.AdminCheckInController, :door} => [:check_in],
    {W.AdminCheckInController, :rotate_door} => [:check_in, :manage_settings],
    {W.AdminCheckInController, :poster} => [:check_in, :manage_settings],
    {W.AdminCheckInController, :update_poster} => [:manage_settings, :manage_locations],
    {W.AdminCheckInController, :rotate_poster} => [:manage_settings, :manage_locations],
    {W.AdminCheckInController, :nfc_tag} => [:check_in, :manage_settings],
    {W.AdminCheckInController, :update_nfc_tag} => [:manage_settings, :manage_locations],
    {W.AdminCheckInController, :rotate_nfc_tag} => [:manage_settings, :manage_locations],
    {W.AdminCheckInController, :revoke_member_code} => [:check_in],
    {W.AdminCheckInController, :scan_member} => [:check_in],
    {W.AdminCheckInController, :check_in_member} => [:check_in],
    {W.AdminCheckInController, :visitors} => [:check_in],
    {W.AdminCheckInController, :settings} => [:manage_settings, :check_in],
    {W.AdminCheckInController, :update_settings} => [:manage_settings],
    {W.AdminClassTypeController, :index} => [:manage_schedule, :run_classes, :manage_workouts],
    {W.AdminClassTypeController, :create} => [:manage_settings],
    {W.AdminClassTypeController, :update} => [:manage_settings],
    {W.AdminClassTypeController, :delete} => [:manage_settings],
    {W.AdminScaleLevelController, :index} => [:manage_workouts, :manage_settings],
    {W.AdminScaleLevelController, :update} => [:manage_settings],

    # Trials (ADR-144)
    {W.AdminTrialController, :policy} => [:manage_settings],
    {W.AdminTrialController, :update_policy} => [:manage_settings],
    {W.AdminTrialController, :queue} => [:run_classes, :manage_memberships, :manage_settings],
    {W.AdminTrialController, :accept} => [:run_classes, :manage_memberships],
    {W.AdminTrialController, :decline} => [:run_classes, :manage_memberships],
    {W.AdminTrialController, :attendance} => [:run_classes],

    # «Κοινότητα» (ADR-143)
    {W.AdminCommunityController, :groups} => [:moderate_community],
    {W.AdminCommunityController, :decide_group} => [:moderate_community],
    {W.AdminCommunityController, :reopen_group} => [:moderate_community],
    {W.AdminCommunityController, :update_settings} => [:manage_community],
    {W.AdminCommunityController, :reports} => [:moderate_community],
    {W.AdminCommunityController, :act_on_report} => [:moderate_community],
    {W.AdminCommunityController, :clubs} => [:moderate_community],
    {W.AdminCommunityController, :create_club} => [:manage_community],
    {W.AdminCommunityController, :club} => [:moderate_community],
    {W.AdminCommunityController, :update_club} => [:manage_community],
    {W.AdminCommunityController, :archive_club} => [:manage_community],
    # ADR-462: a box metric reset (and its undo) is the owner's and admins'.
    {W.AdminAnalyticsController, :reset_metric} => [:reset_analytics],
    {W.AdminAnalyticsController, :undo_reset} => [:reset_analytics],
    {W.AdminCommunityController, :answer_club_request} => [:moderate_community],
    {W.AdminCommunityController, :remove_club_member} => [:moderate_community],

    # Club events (ADR-153): the desk works the door of an event.
    {W.AdminCommunityEventController, :index} => [:manage_events, :check_in, :take_payments],
    {W.AdminCommunityEventController, :show} => [:manage_events, :check_in, :take_payments],
    {W.AdminCommunityEventController, :create} => [:manage_events],
    {W.AdminCommunityEventController, :update} => [:manage_events],
    {W.AdminCommunityEventController, :cancel} => [:manage_events],
    {W.AdminCommunityEventController, :check_in} => [:manage_events, :check_in],
    {W.AdminCommunityEventController, :mark_paid} => [:manage_events, :take_payments],
    {W.AdminCommunityEventController, :remove} => [:manage_events],
    {W.AdminCommunityEventController, :message} => [:manage_events],
    {W.AdminCommunityEventController, :trial_offer} => [:manage_events],
    # ADR-185: the organiser console and co-hosting.
    {W.AdminCommunityEventController, :refund} => [:manage_events, :take_payments],
    {W.AdminCommunityEventController, :finances} => [:manage_events, :take_payments],
    {W.AdminCommunityEventController, :analytics} => [:manage_events, :check_in, :take_payments],
    {W.AdminCommunityEventController, :cohosts} => [:manage_events],
    {W.AdminCommunityEventController, :invite_cohost} => [:manage_events],
    {W.AdminCommunityEventController, :remove_cohost} => [:manage_events],
    {W.AdminCommunityEventController, :cohost_requests} => [:manage_events],
    {W.AdminCommunityEventController, :answer_cohost_request} => [:manage_events],
    {W.AdminCommunityEventController, :cohost_trial_offer} => [:manage_events],

    # Schedule
    {W.AdminScheduleController, :create_slot} => [:manage_schedule],
    {W.AdminScheduleController, :create_series} => [:manage_schedule],
    {W.AdminScheduleController, :update_slot} => [:manage_schedule],
    {W.AdminScheduleController, :change_state} => [:manage_schedule],
    # ADR-176: whoever programmes WODs may link one to a class.
    {W.AdminScheduleController, :link_workout} => [:manage_schedule, :manage_workouts],
    {W.AdminScheduleController, :delete_slot} => [:manage_schedule],
    {W.AdminScheduleController, :approve_booking} => [:run_classes],
    {W.AdminScheduleController, :reject_booking} => [:run_classes],
    {W.AdminScheduleController, :record_attendance} => [:run_classes],
    # ADR-163: coach totals of a class's «τι ένιωσες»; row security decides
    # which entries count (a coach of the gym, the entry's rung).
    {W.AdminWorkoutGoalsController, :class_feedback_summary} => [:manage_workouts, :run_classes],

    # Finance
    {W.AdminFinanceAccountingController, :refund_receipts} => [
      :manage_billing,
      :take_payments,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :refund_receipt} => [
      :manage_billing,
      :take_payments,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :refund_receipt_document} => [
      :manage_billing,
      :take_payments,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :reconciliation_records} => [
      :manage_billing,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :reconciliation_candidates} => [:manage_billing],
    {W.AdminFinanceAccountingController, :record_reconciliation_line} => [:manage_billing],
    {W.AdminFinanceAccountingController, :match_reconciliation} => [:manage_billing],
    {W.AdminFinanceAccountingController, :unmatch_reconciliation} => [:manage_billing],
    {W.AdminFinanceAccountingController, :exports} => [:manage_billing, :view_finance_reports],
    {W.AdminFinanceAccountingController, :request_export} => [
      :manage_billing,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :export_download} => [
      :manage_billing,
      :view_finance_reports
    ],
    {W.AdminFinanceController, :summary} => [:view_finance_reports],
    {W.AdminFiscalController, :countries} => [:view_finance_reports],
    {W.AdminFiscalController, :identity} => [:view_finance_reports],
    {W.AdminFiscalController, :save_identity} => [:manage_billing],
    {W.AdminFiscalController, :documents} => [:view_finance_reports],
    {W.AdminFiscalController, :document} => [:view_finance_reports],
    {W.AdminFiscalController, :credit} => [:manage_billing],
    {W.AdminFiscalController, :verify_journal} => [:manage_billing],
    {W.AdminFiscalController, :closings} => [:view_finance_reports],
    {W.AdminFiscalController, :archive} => [:manage_billing],
    {W.AdminFiscalTaxController, :tax_categories} => [:view_finance_reports],
    {W.AdminFiscalTaxController, :sales_tax_rates} => [:view_finance_reports],
    {W.AdminFiscalTaxController, :save_sales_tax_rates} => [:manage_billing],
    {W.AdminFiscalTaxController, :document_pdf} => [:view_finance_reports],
    {W.AdminFiscalTaxController, :document_html} => [:view_finance_reports],
    {W.AdminFiscalTaxController, :email_document} => [:manage_billing],
    {W.AdminFiscalRegistryController, :connection} => [:view_finance_reports],
    {W.AdminFiscalRegistryController, :save_connection} => [:manage_billing],
    {W.AdminFiscalRegistryController, :lookup} => [:manage_billing],
    # ADR-273: the box's fiscal connections as one set and «Δοκιμή σύνδεσης».
    {W.AdminFiscalConnectionsController, :index} => [:view_finance_reports],
    {W.AdminFiscalConnectionsController, :check} => [:manage_billing],
    {W.AdminFiscalTaxController, :export_formats} => [:view_finance_reports],
    {W.AdminFiscalTaxController, :save_export_settings} => [:manage_billing],
    {W.AdminFiscalTaxController, :export} => [:view_finance_reports],
    {W.AdminFiscalReportingController, :connection} => [:view_finance_reports],
    {W.AdminFiscalReportingController, :save_connection} => [:manage_billing],
    {W.AdminFiscalReportingController, :transmissions} => [:view_finance_reports],
    {W.AdminFiscalReportingController, :retry} => [:manage_billing],
    {W.AdminFiscalEInvoicingController, :connection} => [:view_finance_reports],
    {W.AdminFiscalEInvoicingController, :save_connection} => [:manage_billing],
    {W.AdminFiscalEInvoicingController, :index} => [:view_finance_reports],
    {W.AdminFiscalEInvoicingController, :show} => [:view_finance_reports],
    {W.AdminFiscalEInvoicingController, :retry} => [:manage_billing],
    {W.AdminFiscalTillSigningController, :connection} => [:view_finance_reports],
    {W.AdminFiscalTillSigningController, :save_connection} => [:manage_billing],
    {W.AdminFiscalTillSigningController, :index} => [:view_finance_reports],
    {W.AdminFiscalTillSigningController, :show} => [:view_finance_reports],
    {W.AdminFiscalTillSigningController, :retry} => [:manage_billing],
    {W.AdminFiscalTillSigningController, :null_receipt} => [:manage_billing],
    # ADR-378..380: «Συνδέσεις» (keys act for their maker, so owners and admins).
    {W.AdminIntegrationsController, :catalog} => [:manage_settings],
    {W.AdminIntegrationsController, :keys} => [:manage_settings],
    {W.AdminIntegrationsController, :create_key} => [:manage_settings],
    {W.AdminIntegrationsController, :rotate_key} => [:manage_settings],
    {W.AdminIntegrationsController, :revoke_key} => [:manage_settings],
    {W.AdminIntegrationsController, :webhooks} => [:manage_settings],
    {W.AdminIntegrationsController, :create_webhook} => [:manage_settings],
    {W.AdminIntegrationsController, :update_webhook} => [:manage_settings],
    {W.AdminIntegrationsController, :delete_webhook} => [:manage_settings],
    {W.AdminIntegrationsController, :rotate_webhook_secret} => [:manage_settings],
    {W.AdminIntegrationsController, :test_webhook} => [:manage_settings],
    {W.AdminIntegrationsController, :deliveries} => [:manage_settings],
    {W.AdminIntegrationsController, :delivery} => [:manage_settings],
    {W.AdminIntegrationsController, :replay} => [:manage_settings],
    {W.AdminIntegrationsController, :audience} => [:manage_settings],
    {W.AdminIntegrationsController, :save_audience} => [:manage_settings],
    {W.AdminIntegrationsController, :delete_audience} => [:manage_settings],
    {W.AdminIntegrationsController, :sync_audience} => [:manage_settings],
    {W.AdminIntegrationsController, :rotate_unsubscribe_url} => [:manage_settings],
    # ADR-381: doors per branch (branch managers too), opening from the desk.
    {W.AdminDoorsController, :catalog} => [:manage_settings, :manage_locations, :check_in],
    {W.AdminDoorsController, :index} => [:manage_settings, :manage_locations, :check_in],
    {W.AdminDoorsController, :create} => [:manage_settings, :manage_locations],
    {W.AdminDoorsController, :update} => [:manage_settings, :manage_locations],
    {W.AdminDoorsController, :delete} => [:manage_settings, :manage_locations],
    {W.AdminDoorsController, :rotate_event_token} => [:manage_settings, :manage_locations],
    {W.AdminDoorsController, :unlock} => [:check_in],
    {W.AdminDoorsController, :events} => [:manage_settings, :manage_locations, :check_in],
    # ADR-246/247: online payments.
    {W.AdminPaymentsController, :account} => [:view_finance_reports, :manage_billing],
    {W.AdminPaymentsController, :save_account} => [:manage_billing],
    {W.AdminPaymentsController, :index} => [:view_finance_reports, :manage_billing],
    {W.AdminPaymentsController, :show} => [:view_finance_reports, :manage_billing],
    {W.AdminPaymentsController, :refund} => [:manage_billing],
    {W.AdminPaymentsController, :retry} => [:manage_billing],
    {W.AdminPaymentsController, :save_options} => [:manage_billing],
    # ADR-271: «Τα N πακέτα σου πωλούνται τώρα online» closed.
    {W.AdminPaymentsController, :dismiss_packages_notice} => [:manage_billing],
    {W.AdminPaymentsController, :connect} => [:manage_billing],
    {W.AdminPaymentsController, :disconnect} => [:manage_billing],
    {W.AdminPaymentsController, :attention} => [:manage_billing, :take_payments],
    {W.AdminPaymentsController, :retry_charge} => [:manage_billing],
    {W.AdminPaymentsController, :dismiss_charge} => [:manage_billing, :take_payments],
    {W.AdminPaymentsController, :card_link} => [:manage_billing, :take_payments],
    # ADR-249: Tap to Pay is taking money at the desk, like ADR-222.
    {W.AdminTerminalPaymentsController, :availability} => [:take_payments],
    {W.AdminTerminalPaymentsController, :create} => [:take_payments],
    {W.AdminTerminalPaymentsController, :result} => [:take_payments],
    {W.AdminTerminalPaymentsController, :show} => [:take_payments],
    {W.AdminTerminalPaymentsController, :cancel} => [:take_payments],
    {W.AdminTerminalPaymentsController, :sandbox_complete} => [:take_payments],
    # ADR-272: the receipt by email, «Ποιος;» / «Τι;», guests of the box, tips.
    {W.AdminTerminalPaymentsController, :receipt_email} => [:take_payments],
    {W.AdminDeskBuyersController, :people} => [:take_payments],
    {W.AdminDeskBuyersController, :options} => [:take_payments],
    {W.AdminDeskBuyersController, :make_guest} => [:take_payments],
    {W.AdminTipsController, :index} => [:view_finance_reports, :manage_billing],
    # ADR-341: coach pay and commissions (pay is billing staff's business).
    {W.AdminCoachPayController, :rules} => [:view_finance_reports, :manage_billing],
    {W.AdminCoachPayController, :create_rule} => [:manage_billing],
    {W.AdminCoachPayController, :update_rule} => [:manage_billing],
    {W.AdminCoachPayController, :archive_rule} => [:manage_billing],
    {W.AdminCoachPayController, :periods} => [:view_finance_reports, :manage_billing],
    {W.AdminCoachPayController, :create_period} => [:manage_billing],
    {W.AdminCoachPayController, :period} => [:view_finance_reports, :manage_billing],
    {W.AdminCoachPayController, :calculate} => [:manage_billing],
    {W.AdminCoachPayController, :add_adjustment} => [:manage_billing],
    {W.AdminCoachPayController, :delete_adjustment} => [:manage_billing],
    {W.AdminCoachPayController, :restore_item} => [:manage_billing],
    {W.AdminCoachPayController, :people} => [:view_finance_reports, :manage_billing],
    {W.AdminCoachPayController, :approve} => [:manage_billing],
    {W.AdminCoachPayController, :reopen} => [:manage_billing],
    {W.AdminCoachPayController, :export} => [:view_finance_reports, :manage_billing],
    # ADR-382: lines by hand, gross/net, the PDF, a person's statements and
    # Finance's summary; the catalogue of overtime and allowances is a setting.
    {W.AdminCoachPayController, :add_pay_item_line} => [:manage_billing],
    {W.AdminCoachPayController, :set_line_basis} => [:manage_billing],
    {W.AdminCoachPayController, :payslip} => [:view_finance_reports, :manage_billing],
    {W.AdminCoachPayController, :person_statements} => [:view_finance_reports, :manage_billing],
    {W.AdminCoachPayController, :summary} => [:view_finance_reports, :manage_billing],
    {W.AdminCoachPayController, :items} => [
      :manage_settings,
      :view_finance_reports,
      :manage_billing
    ],
    {W.AdminCoachPayController, :create_item} => [:manage_settings],
    {W.AdminCoachPayController, :update_item} => [:manage_settings],
    {W.AdminCoachPayController, :archive_item} => [:manage_settings],
    # A staff member's own statements: every staff role may be paid (ADR-382);
    # the service only ever reads the caller's own.
    {W.MyCoachPayController, :index} => @own_pay,
    {W.MyCoachPayController, :payslip} => @own_pay,
    # ADR-340: the card surcharge.
    {W.AdminCardSurchargeController, :show} => [:view_finance_reports, :manage_billing],
    {W.AdminCardSurchargeController, :update} => [:manage_billing],
    {W.AdminCardSurchargeController, :quote} => [:take_payments, :manage_billing],
    # ADR-252: documents are box rules (manage_settings: which are
    # mandatory, their text, the booking gate); asking clients to sign and
    # reading who signed is membership work too, and front desk work
    # (request_signatures; the evidence PDF stays with the first two).
    {W.AdminDocumentsController, :index} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    {W.AdminDocumentsController, :show} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    {W.AdminDocumentsController, :version} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    {W.AdminDocumentsController, :request} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    {W.AdminDocumentsController, :requests} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    {W.AdminDocumentsController, :cancel_request} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    {W.AdminDocumentsController, :signatures} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    {W.AdminDocumentsController, :evidence} => [:manage_settings, :manage_memberships],
    {W.AdminDocumentsController, :member} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    {W.AdminDocumentsController, :outstanding} => [
      :manage_settings,
      :manage_memberships,
      :request_signatures
    ],
    # ADR-252: health certificates are health data (GDPR art. 9): dates and
    # files need manage_health_certificates; view_health (coaches, own
    # clients) sees only valid / expired / missing in the list.
    {W.AdminHealthCertificatesController, :index} => [
      :manage_health_certificates,
      :view_health_certificates,
      :view_health
    ],
    # Front desk sees certificates by default (product owner, 2026-10-29):
    # a client's dates and the file; uploading and deleting stay with
    # manage_health_certificates.
    {W.AdminHealthCertificatesController, :client} => [
      :manage_health_certificates,
      :view_health_certificates
    ],
    {W.AdminHealthCertificatesController, :file} => [
      :manage_health_certificates,
      :view_health_certificates
    ],
    # ADR-192: shop reports read like the business statistics; the
    # reconciliation is also a finance check; targets are a setting.
    {W.AdminShopReportController, :reconciliation} => [
      :view_business_analytics,
      :view_finance_reports,
      :manage_shop
    ],
    {W.AdminShopReportController, :put_pricing_target} => [:manage_shop, :manage_settings],
    {W.AdminFinanceController, :operational_queues} => [:view_finance_reports],
    {W.AdminFinanceController, :cleanup_records} => [:manage_billing],
    {W.AdminFinanceController, :purge_record} => [:manage_billing],
    {W.AdminFinanceController, :packages} => [:view_package_catalog],
    # ADR-370/371: programmes are written from WODs and sold like packages.
    {W.AdminProgrammeController, :index} => [:manage_workouts, :view_package_catalog],
    {W.AdminProgrammeController, :show} => [:manage_workouts, :view_package_catalog],
    {W.AdminProgrammeController, :create} => [:manage_workouts],
    {W.AdminProgrammeController, :update} => [:manage_workouts],
    {W.AdminProgrammeController, :publish} => [:manage_packages],
    {W.AdminProgrammeController, :archive} => [:manage_packages],
    {W.AdminProgrammeController, :restore} => [:manage_packages],
    {W.AdminProgrammeController, :purchases} => [:take_payments, :manage_billing],
    {W.AdminProgrammeController, :refund} => [:manage_billing],
    {W.AdminProgrammeController, :reviews} => [:manage_workouts, :manage_packages],
    {W.AdminProgrammeController, :moderate_review} => [:manage_packages],
    # ADR-541: the cover is written with the programme.
    {W.AdminProgrammeController, :cover_upload} => [:manage_workouts],
    {W.AdminProgrammeController, :complete_cover} => [:manage_workouts],
    {W.AdminProgrammeController, :set_cover} => [:manage_workouts],
    {W.AdminProgrammeController, :remove_cover} => [:manage_workouts],
    # ADR-167: seasons are sold like packages; places are answered like payments.
    {W.AdminSeasonController, :index} => [:view_package_catalog, :take_payments],
    {W.AdminSeasonController, :show} => [:view_package_catalog, :take_payments],
    {W.AdminSeasonController, :create} => [:manage_packages],
    {W.AdminSeasonController, :update} => [:manage_packages],
    {W.AdminSeasonController, :confirm} => [:take_payments, :manage_memberships],
    {W.AdminSeasonController, :decline} => [:take_payments, :manage_memberships],
    {W.AdminSeasonController, :remove} => [:take_payments, :manage_memberships],
    {W.AdminFinanceController, :package_catalog} => [:view_package_catalog],
    {W.AdminFinanceController, :package} => [:view_package_catalog],
    {W.AdminFinanceController, :create_package} => [:manage_packages],
    {W.AdminFinanceController, :update_package} => [:manage_packages],
    {W.AdminFinanceController, :retire_package} => [:manage_packages],
    {W.AdminFinanceController, :backfill_entitlements} => [:manage_billing],
    {W.AdminFinanceController, :members} => [:manage_billing, :take_payments],
    {W.AdminFinanceController, :member} => [:manage_billing, :take_payments],
    {W.AdminFinanceController, :update_member} => [:manage_billing],
    # ADR-274: values set by hand; the history is read with the ledger.
    {W.AdminFinanceController, :set_member_override} => [:manage_billing],
    {W.AdminFinanceController, :reset_member_override} => [:manage_billing],
    {W.AdminFinanceController, :member_overrides} => [:manage_billing, :take_payments],
    {W.AdminFinanceController, :set_member_auto_renew} => [:manage_billing],
    {W.AdminFinanceController, :mark_member_left} => [:manage_billing],
    {W.AdminFinanceController, :undo_member_left} => [:manage_billing],
    {W.AdminFinanceController, :assign_package} => [:take_payments],
    {W.AdminFinanceController, :record_payment} => [:take_payments],
    {W.AdminFinanceController, :create_receipt} => [:take_payments],
    # ADR-222: front desk takes the money and leaves the document the billing
    # setup calls for, a paid invoice included.
    {W.AdminFinanceController, :receive_payment} => [:take_payments],
    # ADR-291: «Περιμένουν πληρωμή» and its «Είσπραξη».
    {W.AdminPackageRequestController, :index} => [
      :take_payments,
      :manage_billing,
      :view_finance_reports
    ],
    {W.AdminPackageRequestController, :collect} => [:take_payments],
    {W.AdminFinanceController, :redeem_promotion} => [:take_payments],
    {W.AdminFinanceController, :create_invoice} => [:manage_billing],
    {W.AdminFinanceController, :generate_renewal_invoice} => [:manage_billing],
    {W.AdminFinanceController, :create_manual_credit} => [:manage_billing],
    {W.AdminFinanceController, :apply_credit_to_payment} => [:manage_billing],
    {W.AdminFinanceController, :reverse_payment} => [:manage_billing],
    {W.AdminFinanceController, :apply_credit_to_invoice} => [:manage_billing],
    {W.AdminFinanceController, :reverse_credit_ledger_entry} => [:manage_billing],
    {W.AdminFinanceController, :update_invoice} => [:manage_billing],
    {W.AdminFinanceController, :issue_invoice} => [:manage_billing],
    {W.AdminFinanceController, :void_invoice} => [:manage_billing],
    {W.AdminFinanceController, :invoice_upload_url} => [:manage_billing],
    {W.AdminFinanceController, :invoice_upload_complete} => [:manage_billing],
    {W.AdminFinanceController, :invoice_download_url} => [:manage_billing],
    {W.AdminFinanceController, :promotions} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_promotion} => [:manage_promotions],
    {W.AdminFinanceController, :promotion_codes} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_promotion_code} => [:manage_promotions],
    {W.AdminFinanceController, :referral_programs} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_referral_program} => [:manage_promotions],
    {W.AdminFinanceController, :update_referral_program} => [:manage_promotions],
    {W.AdminFinanceController, :referrals} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_referral} => [:manage_promotions],
    {W.AdminFinanceController, :update_referral_status} => [:manage_promotions],
    {W.AdminFinanceController, :referral_rewards} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_referral_reward} => [:manage_promotions],
    {W.AdminFinanceController, :update_referral_reward_status} => [:manage_promotions],
    # ADR-156: invites.
    {W.AdminReferralController, :index} => [:manage_promotions, :view_promotions],
    {W.AdminReferralController, :approve} => [:manage_promotions],
    {W.AdminReferralController, :reject} => [:manage_promotions],
    {W.AdminReferralController, :given} => [:manage_promotions],
    {W.AdminReferralController, :reassign} => [:manage_promotions],
    {W.AdminReferralController, :friend_gift} => [:manage_promotions],

    # Staff appointments: front desk books and cancels for clients.
    {W.AppointmentsController, :slots} => [:manage_appointments, :book_for_clients],
    {W.AppointmentsController, :book_for_client} => [:manage_appointments, :book_for_clients],
    {W.AppointmentsController, :cancel} => [:manage_appointments, :book_for_clients],

    # A client's journal through the coach seam (ADR-139 §6)
    {W.JournalController, :client_journal} => [:manage_coaching],
    # ADR-158: health data; the use case also requires the coach role.
    {W.ClientBodyController, :index} => [:view_health],
    {W.ClientBodyController, :show} => [:view_health],
    {W.ClientBodyController, :series} => [:view_health],
    # ADR-160: the weekly wellness summary; the use case also requires the
    # coach role and the client's grant.
    {W.ClientWellnessSummaryController, :show} => [:view_health],
    # ADR-165: coverage, qualities and load from shared entries; the use
    # case also requires the coach role and the client in scope.
    {W.TrainingDepthController, :client} => [:view_client_training],
    # ADR-395: a client's fitness card; the use case also requires an
    # active coaching relationship (owners who do not coach them get 403).
    {W.ClientFitnessDisplayController, :show} => [:view_client_training],
    {W.ClientFitnessDisplayController, :update} => [:manage_coaching],

    # Private coach notes (ADR-101)
    # ADR-359 (CP-E5): staff notes are read and written by anyone who sees
    # the member in the directory (front desk included); the service keeps
    # private notes to ADR-101's readers and edits to the author.
    {W.CoachNotesController, :index} => [:write_coach_notes, :read_coach_notes, :view_directory],
    {W.CoachNotesController, :create} => [:write_coach_notes, :view_directory],
    {W.CoachNotesController, :update} => [:write_coach_notes, :view_directory],
    {W.CoachNotesController, :delete} => [:write_coach_notes, :view_directory],
    {W.CoachNotesController, :reads} => [:write_coach_notes],
    {W.CoachNotesController, :visibility} => [:write_coach_notes],

    # A client's weekly goal (ADR-229); the scope check narrows to own clients.
    {W.TrainingGoalController, :client_show} => [:manage_coaching],
    {W.TrainingGoalController, :client_update} => [:manage_coaching],

    # Cleaning log (ADR-102)
    {W.CleaningController, :areas} => [:record_cleaning, :review_cleaning, :manage_cleaning_areas],
    {W.CleaningController, :create_area} => [:manage_cleaning_areas],
    {W.CleaningController, :update_area} => [:manage_cleaning_areas],
    {W.CleaningController, :archive_area} => [:manage_cleaning_areas],
    {W.CleaningController, :entries} => [:record_cleaning, :review_cleaning],
    {W.CleaningController, :start} => [:record_cleaning],
    {W.CleaningController, :finish} => [:record_cleaning],
    # ADR-202: the cleaning schedule (owners, admins, front desk) and «Σήμερα».
    {W.CleaningController, :schedules} => [
      :record_cleaning,
      :review_cleaning,
      :manage_cleaning_schedule
    ],
    {W.CleaningController, :put_schedule} => [:manage_cleaning_schedule],
    {W.CleaningController, :delete_schedule} => [:manage_cleaning_schedule],
    {W.CleaningController, :today} => [
      :record_cleaning,
      :review_cleaning,
      :manage_cleaning_schedule
    ],

    # Spaces (ADR-202): whoever plans classes also reads the spaces.
    {W.SpacesController, :index} => [
      :view_spaces,
      :manage_spaces,
      :edit_space_details,
      :set_space_unavailable,
      :manage_schedule
    ],
    {W.SpacesController, :show} => [
      :view_spaces,
      :manage_spaces,
      :edit_space_details,
      :set_space_unavailable,
      :manage_schedule
    ],
    {W.SpacesController, :create} => [:manage_spaces],
    # Front desk edits the details only (checked in SpaceDirectory).
    {W.SpacesController, :update} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :archive} => [:manage_spaces],
    {W.SpacesController, :restore} => [:manage_spaces],
    {W.SpacesController, :make_unavailable} => [:manage_spaces, :set_space_unavailable],
    {W.SpacesController, :delete_unavailability} => [:manage_spaces, :set_space_unavailable],
    {W.SpacesController, :floor_plan_upload} => [:manage_spaces],
    {W.SpacesController, :complete_floor_plan_upload} => [:manage_spaces],
    {W.SpacesController, :create_floor_plan} => [:manage_spaces],
    {W.SpacesController, :update_floor_plan} => [:manage_spaces],
    {W.SpacesController, :delete_floor_plan} => [:manage_spaces],
    # ADR-290: owners, admins and front desk manage room photos and cleaning
    # points; a janitor also uploads the "after" photo of a point.
    {W.SpacesController, :settings} => [:manage_spaces],
    {W.SpacesController, :put_settings} => [:manage_spaces],
    {W.SpacesController, :space_photo_upload} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :complete_space_photo_upload} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :cleaning_photo_upload} => [
      :manage_spaces,
      :edit_space_details,
      :record_cleaning
    ],
    {W.SpacesController, :complete_cleaning_photo_upload} => [
      :manage_spaces,
      :edit_space_details,
      :record_cleaning
    ],
    {W.SpacesController, :add_photo} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :update_photo} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :delete_photo} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :order_photos} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :add_point} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :update_point} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :delete_point} => [:manage_spaces, :edit_space_details],
    {W.SpacesController, :order_points} => [:manage_spaces, :edit_space_details],

    # Invitations
    {W.OrganizationAccessController, :issue} => [:invite_clients],
    {W.OrganizationAccessController, :list_invitations} => [:invite_clients],
    {W.OrganizationAccessController, :show_join_link} => [:invite_clients],
    {W.OrganizationAccessController, :update_join_link} => [:invite_clients],
    {W.OrganizationAccessController, :revoke} => [:invite_clients],
    {W.OrganizationAccessController, :bulk_invite} => [:invite_clients],
    {W.OrganizationAccessController, :resend} => [:invite_clients],
    # ADR-104: the whole team reports; front desk, admins and owners manage.
    {W.InventoryController, :machines} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :machine_events} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :log_machine_event} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :machine_photo_upload} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :complete_machine_photo_upload} => [
      :manage_inventory,
      :report_inventory
    ],
    {W.InventoryController, :supplies} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :report_low} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :supply_reports} => [:manage_inventory, :report_inventory],
    # ADR-202: where machines stand; who manages inventory or spaces.
    {W.InventoryController, :place_machine} => [:manage_inventory, :manage_spaces],
    # ADR-190: the shop. The desk sells (sell_shop); the catalog, stock and
    # refunds are manage_shop (refunds also need take_payments, checked in
    # the controller); Finance readers see the per-stream totals and lineage.
    {W.ShopController, :products} => [:manage_shop, :sell_shop],
    {W.ShopController, :product} => [:manage_shop, :sell_shop],
    {W.ShopController, :orders} => [:manage_shop, :sell_shop],
    {W.ShopController, :order} => [:manage_shop, :sell_shop],
    {W.ShopController, :mark_ready} => [:manage_shop, :sell_shop],
    {W.ShopController, :record_payment} => [:manage_shop, :sell_shop],
    {W.ShopController, :pick_up} => [:manage_shop, :sell_shop],
    {W.ShopController, :cancel} => [:manage_shop, :sell_shop],
    {W.ShopController, :desk_sale} => [:manage_shop, :sell_shop],
    {W.ShopController, :payment_methods} => [:manage_shop, :sell_shop],
    {W.ShopController, :ready_orders} => [:manage_shop, :sell_shop, :check_in],
    {W.ShopController, :set_fiscal_receipt} => [:manage_shop, :sell_shop],
    {W.ShopController, :lineage} => [:manage_shop, :view_finance_reports],
    {W.ShopController, :revenue_streams} => [:view_finance_reports, :manage_shop]
  }

  @doc "Capabilities that each grant the route, or nil when unlisted."
  def for_action(controller, action) do
    Map.get(@actions, {controller, action}) || Map.get(@controller_defaults, controller)
  end
end
