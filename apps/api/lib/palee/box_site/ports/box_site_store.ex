defmodule Palee.BoxSite.Ports.BoxSiteStore do
  @moduledoc """
  Persistence of the box's website (ADR-352..354). Tenant callbacks take the
  tenant context first and run under its row-level security. The three
  lookup callbacks without a context go through SECURITY DEFINER functions
  and answer only what is public (a host's box, the ops list, due boxes).

  Claims move due outbox rows to `sending` and spend one attempt in one
  statement (`FOR UPDATE SKIP LOCKED`), so two workers never deliver the
  same submission at once.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  # Settings
  @callback get_settings(context()) :: map() | nil
  @doc "The Conversions API token, decrypted, or nil (never leaves the server)."
  @callback conversions_api_token(context()) :: String.t() | nil
  @callback save_settings(context(), map(), lock_version :: non_neg_integer()) ::
              {:ok, map()} | {:error, :stale | term()}

  # Domains
  @callback list_domains(context()) :: [map()]
  @callback get_domain(context(), id()) :: map() | nil
  @callback insert_domain(context(), map()) :: {:ok, map()} | {:error, :host_taken | term()}
  @callback update_domain(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback make_primary(context(), id()) :: {:ok, map()} | {:error, term()}
  @callback delete_domain(context(), id()) :: :ok | {:error, :not_found}
  @callback due_domains(context(), DateTime.t(), pos_integer()) :: [map()]

  # ADR-398: the outbox of cluster calls (one waiting op per host).
  @callback queue_ingress_op(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback claim_ingress_ops(context(), DateTime.t(), pos_integer()) :: [map()]
  @callback finish_ingress_op(context(), id(), :done | map()) :: :ok | {:error, term()}

  # Form outbox
  @callback insert_submission(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback claim_submissions(context(), DateTime.t(), pos_integer()) :: [map()]
  @callback finish_submission(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback claim_conversions(context(), DateTime.t(), pos_integer()) :: [map()]
  @callback redact_failed_before(context(), DateTime.t(), DateTime.t()) :: non_neg_integer()
  @callback submission_counts(context(), DateTime.t()) :: %{String.t() => non_neg_integer()}

  # Consent log
  @callback insert_consent(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback latest_consent(context(), visitor_id :: id()) :: map() | nil
  @callback delete_consents_before(context(), DateTime.t()) :: non_neg_integer()
  @callback consent_counts(context(), DateTime.t()) :: %{String.t() => non_neg_integer()}

  # Lookups without a tenant context
  @callback site_by_host(String.t()) :: map() | nil
  @callback primary_host(id()) :: String.t() | nil
  @callback domains_for_ops(String.t()) :: [map()]
  @callback due_organizations(DateTime.t()) :: [id()]
  @callback ingress_hosts() :: [%{organization_id: id(), host: String.t()}]
end
