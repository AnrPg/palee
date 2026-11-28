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
  Closes as `activated` every pending request the box already answered:
  the person holds the package asked for through a subscription assigned,
  or paid for, after the request was made. Returns them.
  """
  @callback fulfil_answered(DateTime.t()) :: [request()]

  @doc """
  ADR-717: counts a class booked while the person's request waits, against
  the box's `allowed` number (per person and box, for good). On success
  `{:ok, {:claimed, id}}` (give it back with `release_wait_booking/1` if
  the booking is not made) or `{:ok, {:counted, id}}` (this class was
  already counted, e.g. booked again after a cancel). Otherwise `{:error,
  :wait_bookings_used}` or `{:error, :no_pending_request}`.
  """
  @callback claim_wait_booking(
              Ecto.UUID.t(),
              Ecto.UUID.t(),
              non_neg_integer(),
              Date.t(),
              DateTime.t()
            ) ::
              {:ok, {:claimed | :counted, Ecto.UUID.t()}}
              | {:error, :wait_bookings_used | :no_pending_request}

  @doc "Gives a counted class back when the booking it was taken for was not made."
  @callback release_wait_booking(Ecto.UUID.t()) :: :ok

  @doc "How many classes the person booked while waiting, at this box."
  @callback wait_bookings_used(Ecto.UUID.t()) :: non_neg_integer()

  @doc "The same for several people: `%{user_id => count}` (missing = 0)."
  @callback wait_bookings_used_by([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => non_neg_integer()}
end
