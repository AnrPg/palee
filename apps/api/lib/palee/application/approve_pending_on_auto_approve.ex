defmodule Palee.Application.ApprovePendingOnAutoApprove do
  @moduledoc """
  ADR-226 follow-up: once a class confirms bookings automatically, no one is
  meant to answer requests any more, so the requests still waiting are
  approved in the order they were made, while seats last. Each one goes
  through `ResolveBooking` (timeout job cancelled, member notified, realtime
  broadcast, analytics). A request that cannot be approved (class full, or
  outside the editor's branches) keeps waiting as before.
  """

  require Logger

  alias Palee.Application.ResolveBooking
  alias Palee.Scheduling

  @spec call(map() | nil, map()) :: :ok
  def call(nil, _slot), do: :ok

  def call(context, %{id: slot_id, auto_approve: true}) do
    case Scheduling.get_slot(context, slot_id) do
      %{auto_approve: true, bookings: bookings} when is_list(bookings) ->
        bookings
        |> Enum.filter(&(&1.status == :pending))
        |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
        |> Enum.reduce_while(:ok, fn booking, :ok -> approve(context, booking) end)

      _other ->
        :ok
    end
  end

  def call(_context, _slot), do: :ok

  defp approve(context, booking) do
    case ResolveBooking.call(context, booking.id, %{action: :approve}) do
      {:ok, _booking, _outcome} ->
        {:cont, :ok}

      {:error, :slot_full} ->
        {:halt, :ok}

      {:error, reason} ->
        Logger.info(
          "auto_approve_pending_skipped booking_id=#{booking.id} reason=#{inspect(reason)}"
        )

        {:cont, :ok}
    end
  end
end
