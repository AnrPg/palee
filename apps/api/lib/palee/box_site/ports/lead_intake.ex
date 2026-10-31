defmodule Palee.BoxSite.Ports.LeadIntake do
  @moduledoc """
  ADR-353: where a website form becomes a lead (CP-C1, the leads context).
  The adapter is chosen by `config :palee, :box_site_lead_intake`.

  `submit/2` runs inside the box's tenant context and must be idempotent on
  `intake.submission_id`: the same id twice returns the same lead.

  Intake (atom keys): `submission_id`, `kind` (`"trial" | "contact"`),
  `source` (`"website_form"`), `name`, `email`, `phone`, `message`,
  `preferred_time`, `class_type_id`, `locale`, `marketing_opt_in`,
  `submitted_at`, `attribution` (`utm_source`, `utm_medium`,
  `utm_campaign`, `utm_term`, `utm_content`, `referrer_host`,
  `landing_path`), `consent` (`text_version`, `text_hash` of the form's
  consent text, either may be nil).

  `{:error, {:rejected, reason}}` is final (bad data); `{:error,
  {:transient, reason}}` is retried with backoff.
  """

  @callback submit(context :: %{organization_id: Ecto.UUID.t()}, intake :: map()) ::
              {:ok, %{lead_id: Ecto.UUID.t()}}
              | {:error, {:rejected, term()}}
              | {:error, {:transient, term()}}
end
