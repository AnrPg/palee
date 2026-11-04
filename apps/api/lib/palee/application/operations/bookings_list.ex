defmodule Palee.Application.Operations.BookingsList do
  @moduledoc "ADR-378 `bookings.list`: the bookings of one class."

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Scheduling

  @impl true
  def spec do
    %{
      name: "bookings.list",
      kind: :query,
      summary: "List a class's bookings",
      description:
        "Every booking of the class, oldest first, with its status. Guests (bookings by name " <>
          "only) have no member_id.",
      capability: [:manage_schedule, :run_classes, :book_for_clients],
      scope: "bookings:read",
      risk: :read,
      data_classes: [:personal],
      http: %{method: :get, path: "/classes/{class_id}/bookings"},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"class_id" => Views.uuid()},
        "required" => ["class_id"]
      },
      output: %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "array", "items" => Views.booking_schema()}},
        "required" => ["data"]
      },
      examples: [%{input: %{"class_id" => "0f8e3c2a-5b1d-4a7e-9c3f-1d2e3f4a5b6c"}, output: %{}}]
    }
  end

  @impl true
  def execute(context, %{"class_id" => class_id}) do
    case Scheduling.get_slot(context, class_id) do
      nil ->
        {:error, :not_found}

      slot ->
        bookings = if is_list(slot.bookings), do: slot.bookings, else: []
        {:ok, %{"data" => Enum.map(bookings, &Views.booking(&1, slot.id))}}
    end
  end
end
