defmodule Palee.Organizations.Queries.ListOwnerUserIds do
  @moduledoc """
  Active owner user ids of one organization (ADR-690: owners hear when the
  Palee team adopts or merges a type the box made). Runs in that
  organization's repo scope, like `ListStaffUserIds`; the organization id
  comes from server-side provenance only.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.OrganizationStore

  def call(organization_id) when is_binary(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      OrganizationStore.list_owner_user_ids(organization_id)
    end)
  end

  def call(_organization_id), do: []
end
