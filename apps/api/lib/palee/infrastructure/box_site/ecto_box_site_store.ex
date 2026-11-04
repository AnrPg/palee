defmodule Palee.Infrastructure.BoxSite.EctoBoxSiteStore do
  @moduledoc "Ecto adapter of the website store (ADR-352..354)."

  @behaviour Palee.BoxSite.Ports.BoxSiteStore

  import Ecto.Query

  alias Palee.BoxSite.{SiteConsent, SiteDomain, SiteSettings, SiteSubmission}
  alias Palee.Repo

  @claim_timeout_seconds 600

  # ── Settings ────────────────────────────────────────────────────────────

  @impl true
  def get_settings(%{organization_id: organization_id}) do
    organization_id |> settings_row() |> settings_map()
  end

  @impl true
  def conversions_api_token(%{organization_id: organization_id}) do
    case settings_row(organization_id) do
      %SiteSettings{conversions_api_token: token} -> token
      nil -> nil
    end
  end

  @impl true
  def save_settings(%{organization_id: organization_id}, changes, lock_version) do
    case settings_row(organization_id) do
      nil when lock_version in [0, nil] ->
        %SiteSettings{organization_id: organization_id}
        |> SiteSettings.changeset(changes)
        |> Repo.insert()

      nil ->
        {:error, :stale}

      %SiteSettings{lock_version: ^lock_version} = row ->
        row |> SiteSettings.changeset(changes) |> Repo.update()

      %SiteSettings{} ->
        {:error, :stale}
    end
    |> case do
      {:ok, row} -> {:ok, settings_map(row)}
      {:error, :stale} -> {:error, :stale}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @impl true
  def claim_template_notice(%{organization_id: organization_id}, now) do
    {count, _rows} =
      SiteSettings
      |> where([s], s.organization_id == ^organization_id)
      |> where([s], s.template_notice and is_nil(s.template_notice_sent_at))
      |> Repo.update_all(set: [template_notice_sent_at: now])

    count == 1
  end

  defp settings_row(organization_id),
    do: Repo.one(from s in SiteSettings, where: s.organization_id == ^organization_id)

  defp settings_map(nil), do: nil

  defp settings_map(%SiteSettings{} = row) do
    row
    |> Map.from_struct()
    |> Map.drop([:__meta__, :conversions_api_token, :template_notice_sent_at])
    |> Map.put(:faq, Map.get(row.faq || %{}, "entries", []))
    |> Map.put(:has_conversions_api_token, not is_nil(row.conversions_api_token))
  end

  # ── Domains ─────────────────────────────────────────────────────────────

  @impl true
  def list_domains(%{organization_id: organization_id}) do
    SiteDomain
    |> where([d], d.organization_id == ^organization_id)
    |> order_by([d], desc: d.primary, asc: d.inserted_at)
    |> Repo.all()
    |> Enum.map(&domain_map/1)
  end

  @impl true
  def get_domain(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %SiteDomain{} = domain <- domain_row(organization_id, id) do
      domain_map(domain)
    else
      _missing -> nil
    end
  end

  @impl true
  def insert_domain(%{organization_id: organization_id}, attrs) do
    %SiteDomain{organization_id: organization_id}
    |> SiteDomain.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, domain} ->
        {:ok, domain_map(domain)}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :host), do: {:error, :host_taken}, else: {:error, changeset}
    end
  end

  @impl true
  def update_domain(%{organization_id: organization_id}, id, changes) do
    case domain_row(organization_id, id) do
      nil ->
        {:error, :not_found}

      domain ->
        domain
        |> SiteDomain.changeset(changes)
        |> Repo.update()
        |> case do
          {:ok, domain} -> {:ok, domain_map(domain)}
          error -> error
        end
    end
  end

  @impl true
  def make_primary(%{organization_id: organization_id} = context, id) do
    Repo.transaction(fn ->
      case domain_row(organization_id, id) do
        nil ->
          Repo.rollback(:not_found)

        _domain ->
          SiteDomain
          |> where([d], d.organization_id == ^organization_id and d.primary)
          |> Repo.update_all(set: [primary: false])

          SiteDomain
          |> where([d], d.organization_id == ^organization_id and d.id == ^id)
          |> Repo.update_all(set: [primary: true, updated_at: DateTime.utc_now()])

          get_domain(context, id)
      end
    end)
  end

  @impl true
  def delete_domain(%{organization_id: organization_id}, id) do
    Repo.transaction(fn ->
      case domain_row(organization_id, id) do
        nil ->
          Repo.rollback(:not_found)

        domain ->
          Repo.delete!(domain)

          # The other host becomes primary when the primary one goes.
          if domain.primary do
            SiteDomain
            |> where([d], d.organization_id == ^organization_id)
            |> order_by([d], asc: d.inserted_at)
            |> limit(1)
            |> Repo.one()
            |> then(&(&1 && Repo.update!(Ecto.Changeset.change(&1, primary: true))))
          end

          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  @impl true
  def due_domains(%{organization_id: organization_id}, now, limit) do
    SiteDomain
    |> where([d], d.organization_id == ^organization_id)
    |> where([d], d.status in ["pending_dns", "pending_tls", "active", "broken"])
    |> where([d], d.next_check_at <= ^now)
    |> order_by([d], asc: d.next_check_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&domain_map/1)
  end

  defp domain_row(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.one(
          from d in SiteDomain, where: d.organization_id == ^organization_id and d.id == ^id
        )

      :error ->
        nil
    end
  end

  defp domain_map(%SiteDomain{} = domain),
    do: domain |> Map.from_struct() |> Map.delete(:__meta__)

  # ── Form outbox ─────────────────────────────────────────────────────────

  @impl true
  def insert_submission(%{organization_id: organization_id}, attrs) do
    %SiteSubmission{organization_id: organization_id, id: Map.get(attrs, :id)}
    |> SiteSubmission.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, submission_map(row)}
      error -> error
    end
  end

  @impl true
  def claim_submissions(%{organization_id: organization_id}, now, limit) do
    stale = DateTime.add(now, -@claim_timeout_seconds, :second)

    candidates =
      SiteSubmission
      |> where([s], s.organization_id == ^organization_id)
      |> where(
        [s],
        (s.status == "pending" and s.next_attempt_at <= ^now) or
          (s.status == "sending" and s.claimed_at < ^stale)
      )
      |> order_by([s], asc: s.next_attempt_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([s], s.id)

    {_count, rows} =
      SiteSubmission
      |> where([s], s.id in subquery(candidates))
      |> select([s], s)
      |> Repo.update_all(
        set: [status: "sending", claimed_at: now, updated_at: now],
        inc: [attempts: 1]
      )

    Enum.map(rows, &submission_map/1)
  end

  @impl true
  def claim_conversions(%{organization_id: organization_id}, now, limit) do
    stale = DateTime.add(now, -@claim_timeout_seconds, :second)

    candidates =
      SiteSubmission
      |> where([s], s.organization_id == ^organization_id)
      |> where(
        [s],
        (s.conversion_status == "pending" and s.conversion_next_at <= ^now) or
          (s.conversion_status == "sending" and s.conversion_claimed_at < ^stale)
      )
      |> order_by([s], asc: s.conversion_next_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([s], s.id)

    {_count, rows} =
      SiteSubmission
      |> where([s], s.id in subquery(candidates))
      |> select([s], s)
      |> Repo.update_all(
        set: [conversion_status: "sending", conversion_claimed_at: now, updated_at: now],
        inc: [conversion_attempts: 1]
      )

    Enum.map(rows, &submission_map/1)
  end

  @impl true
  def finish_submission(%{organization_id: organization_id}, id, changes) do
    case Repo.one(
           from s in SiteSubmission, where: s.organization_id == ^organization_id and s.id == ^id
         ) do
      nil ->
        {:error, :not_found}

      row ->
        row
        |> SiteSubmission.changeset(changes)
        |> Repo.update()
        |> case do
          {:ok, row} -> {:ok, submission_map(row)}
          error -> error
        end
    end
  end

  @impl true
  def redact_failed_before(%{organization_id: organization_id}, cutoff, now) do
    {count, _rows} =
      SiteSubmission
      |> where([s], s.organization_id == ^organization_id)
      |> where([s], s.status == "failed" and is_nil(s.redacted_at) and s.submitted_at < ^cutoff)
      |> Repo.update_all(
        set: [
          name: nil,
          email: nil,
          phone: nil,
          message: nil,
          preferred_time: nil,
          conversion_payload: nil,
          redacted_at: now,
          updated_at: now
        ]
      )

    count
  end

  @impl true
  def submission_counts(%{organization_id: organization_id}, since) do
    SiteSubmission
    |> where([s], s.organization_id == ^organization_id and s.submitted_at >= ^since)
    |> group_by([s], s.status)
    |> select([s], {s.status, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp submission_map(%SiteSubmission{} = row),
    do: row |> Map.from_struct() |> Map.delete(:__meta__)

  # ── Consent log ─────────────────────────────────────────────────────────

  @impl true
  def insert_consent(%{organization_id: organization_id}, attrs) do
    %SiteConsent{organization_id: organization_id}
    |> SiteConsent.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, consent_map(row)}
      error -> error
    end
  end

  @impl true
  def latest_consent(%{organization_id: organization_id}, visitor_id) do
    case Ecto.UUID.cast(visitor_id || "") do
      {:ok, visitor_id} ->
        SiteConsent
        |> where([c], c.organization_id == ^organization_id and c.visitor_id == ^visitor_id)
        |> order_by([c], desc: c.recorded_at)
        |> limit(1)
        |> Repo.one()
        |> then(&(&1 && consent_map(&1)))

      :error ->
        nil
    end
  end

  @impl true
  def delete_consents_before(%{organization_id: organization_id}, cutoff) do
    {count, _rows} =
      SiteConsent
      |> where([c], c.organization_id == ^organization_id and c.recorded_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  @impl true
  def consent_counts(%{organization_id: organization_id}, since) do
    SiteConsent
    |> where([c], c.organization_id == ^organization_id and c.recorded_at >= ^since)
    |> group_by([c], c.action)
    |> select([c], {c.action, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp consent_map(%SiteConsent{} = row), do: row |> Map.from_struct() |> Map.delete(:__meta__)

  # ── Lookups without a tenant session (SECURITY DEFINER) ─────────────────

  @impl true
  def site_by_host(host) when is_binary(host) do
    case Repo.query!(
           "SELECT organization_id, slug, host, status, is_primary FROM palee_site_by_host($1)",
           [host]
         ) do
      %{rows: [[id, slug, host, status, primary]]} ->
        %{
          organization_id: Ecto.UUID.load!(id),
          slug: slug,
          host: host,
          status: status,
          primary: primary
        }

      _none ->
        nil
    end
  end

  @impl true
  def primary_host(organization_id) do
    case Repo.query!("SELECT palee_site_primary_host($1)", [Ecto.UUID.dump!(organization_id)]) do
      %{rows: [[host]]} -> host
      _none -> nil
    end
  end

  @impl true
  def domains_for_ops(status) do
    %{rows: rows} =
      Repo.query!(
        "SELECT host, slug, status, verified_at, updated_at FROM palee_site_domains_for_ops($1)",
        [status]
      )

    Enum.map(rows, fn [host, slug, status, verified_at, updated_at] ->
      %{host: host, slug: slug, status: status, verified_at: verified_at, updated_at: updated_at}
    end)
  end

  @impl true
  def due_organizations(now) do
    %{rows: rows} =
      Repo.query!("SELECT organization_id FROM palee_box_site_due_organizations($1)", [now])

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  @impl true
  def template_notices_due do
    %{rows: rows} =
      Repo.query!("SELECT organization_id FROM palee_box_site_template_notices_due()", [])

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end
end
