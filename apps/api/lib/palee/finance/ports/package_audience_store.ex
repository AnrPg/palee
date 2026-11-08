defmodule Palee.Finance.Ports.PackageAudienceStore do
  @moduledoc """
  ADR-553: where a box keeps who sees its subscription packages: its own
  audience, each package's audience and the person exceptions. Every call
  runs inside the caller's tenant scope (`Finance.with_tenant_context/2`).
  """

  @doc "`%{box: audience, packages: %{id => audience | nil}, exceptions: [map]}`."
  @callback load() :: map()

  @callback set_box(String.t()) :: {:ok, String.t()} | {:error, term()}

  @callback set_package(Ecto.UUID.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}

  @doc "Adds or changes one person's exception (on a package, or the box with `nil`)."
  @callback put_exception(map()) :: {:ok, map()} | {:error, term()}

  @callback delete_exception(Ecto.UUID.t()) :: :ok | {:error, :not_found}

  @doc """
  One person's subscriptions at the box (`membership_package_id`, `status`,
  `starts_on`, `inserted_at`) and whether they are still a box member.
  """
  @callback holdings(Ecto.UUID.t()) :: %{subscriptions: [map()], member?: boolean()}
end
