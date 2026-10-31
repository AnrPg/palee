defmodule Palee.Application.Operations.BookingsCreate do
  @moduledoc """
  ADR-378 `bookings.create`: books a member into a class as staff would
  (wraps `PlaceMemberInClass`, ADR-232): the regular checks apply (open,
  a free place, the member's package covers it), the booking window does
  not.
  """

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Application.PlaceMemberInClass
  alias Palee.Scheduling

  @impl true
  def spec do
    %{
      name: "bookings.create",
      kind: :command,
      summary: "Book a member into a class",
      description:
        "Books the member into the class, approved at once, using a visit of their package. " <>
          "Refused when the class is full, closed or past, or the package does not cover it " <>
          "(the problem's code says which). Undo with bookings.cancel.",
      capability: [:book_for_clients, :manage_schedule],
      scope: "bookings:write",
      risk: :write_reversible,
      data_classes: [:personal],
      http: %{method: :post, path: "/bookings", status: 201},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"class_id" => Views.uuid(), "member_id" => Views.uuid()},
        "required" => ["class_id", "member_id"]
      },
      output: Views.booking_schema(),
      examples: [
        %{
          input: %{
            "class_id" => "0f8e3c2a-5b1d-4a7e-9c3f-1d2e3f4a5b6c",
            "member_id" => "6a1c3b52-8d0e-4c5c-9d4f-2f5a3e8b9c10"
          },
          output: %{}
        }
      ]
    }
  end

  @impl true
  def preview(context, input) do
    case Scheduling.get_slot(context, input["class_id"]) do
      nil -> {:error, :not_found}
      slot -> {:ok, %{"would" => "book the member", "class" => Views.class(slot), "member_id" => input["member_id"]}}
    end
  end

  @impl true
  def execute(context, input) do
    with {:ok, %{booking: booking}} <-
           PlaceMemberInClass.call(context, input["member_id"], %{"slot_id" => input["class_id"]}) do
      {:ok, Views.booking(booking, input["class_id"])}
    end
  end
end
