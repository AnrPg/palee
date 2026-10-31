defmodule Palee.Application.Operations.BookingsCancel do
  @moduledoc """
  ADR-378 `bookings.cancel`: staff cancel a member's booking (wraps
  `WithdrawBooking` as staff): the visit goes back to the package, the
  waitlist moves up and the member is told, as when staff remove them.
  """

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Application.WithdrawBooking
  alias Palee.Scheduling

  @impl true
  def spec do
    %{
      name: "bookings.cancel",
      kind: :command,
      summary: "Cancel a booking",
      description:
        "Cancels the booking for the member; it is never a late cancellation, since the box " <>
          "cancelled it. The member is notified and the next on the waitlist gets the place.",
      capability: [:book_for_clients, :manage_schedule],
      scope: "bookings:write",
      risk: :outward,
      data_classes: [:personal],
      http: %{method: :delete, path: "/bookings/{id}"},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"id" => Views.uuid()},
        "required" => ["id"]
      },
      output: Views.booking_schema(),
      examples: [%{input: %{"id" => "9b2f4d6e-1a3c-4e5f-8a7b-6c5d4e3f2a1b"}, output: %{}}]
    }
  end

  @impl true
  def preview(context, %{"id" => id}) do
    case Scheduling.get_booking(context, id) do
      nil -> {:error, :not_found}
      booking -> {:ok, %{"would" => "cancel the booking", "booking" => Views.booking(booking)}}
    end
  end

  @impl true
  def execute(context, %{"id" => id}) do
    with %{user_id: user_id} = booking when is_binary(user_id) <-
           Scheduling.get_booking(context, id) || {:error, :not_found},
         {:ok, booking, withdrawn, late?} <-
           WithdrawBooking.write(context, user_id, booking.id, late_cancellation: false) do
      WithdrawBooking.announce(context, booking, withdrawn, late?, :staff)
      {:ok, Views.booking(withdrawn)}
    else
      %{} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end
end
