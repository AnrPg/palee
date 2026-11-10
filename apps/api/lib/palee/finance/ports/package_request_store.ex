defmodule Palee.Finance.Ports.PackageRequestStore do
  @moduledoc """
  ADR-291: where packages waiting to be paid at the front desk are kept.
  Every call runs inside the caller's tenant scope (`Finance.with_tenant_context/2`).
  Requests are returned as plain maps.
  """

  @type request :: map()

  @doc """
  Creates a pending request, or returns the person's open one for that
  package. `params.today` (box-local) lets a pending request whose hold
  already ended be closed as `lapsed` and replaced.
  """
  @callback request(map()) :: {:ok, request(), :created | :existing} | {:error, term()}

  @callback get(Ecto.UUID.t()) :: request() | nil

  @doc "Pending requests held on or after `today`, oldest first; `user_id` narrows to one person."
  @callback list_open(Date.t(), keyword()) :: [request()]

  @doc "Closes a pending request (`cancelled`, `activated`, `lapsed`) under a row lock."
  @callback close(Ecto.UUID.t(), String.t(), map()) :: {:ok, request()} | {:error, term()}

  @doc "Closes as `lapsed` every pending request whose hold ended before `today`; returns them."
  @callback lapse_before(Date.t(), DateTime.t()) :: [request()]

  @doc """
  ADR-633: takes the person's one class while their request waits, on the
  oldest request open on `today`: `{:ok, request}`, or `{:error,
  :first_class_used}` (already taken at this box, by any request) or
  `{:error, :no_pending_request}`.
  """
  @callback claim_first_class(Ecto.UUID.t(), Ecto.UUID.t(), Date.t(), DateTime.t()) ::
              {:ok, request()} | {:error, :first_class_used | :no_pending_request}

  @doc "Gives the one class back when the booking it was taken for was not made."
  @callback release_first_class(Ecto.UUID.t()) :: :ok

  @doc "The request the person's one class was taken on at this box, if any."
  @callback first_class(Ecto.UUID.t()) :: request() | nil
end
