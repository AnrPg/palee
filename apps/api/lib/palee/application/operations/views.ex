defmodule Palee.Application.Operations.Views do
  @moduledoc """
  The public API v1's representation of each object (ADR-378), shared by
  the operations and their schemas. Fields are whitelisted here: nothing
  reaches an integration unless it is named below, so an internal field
  added later never leaks. Times are UTC ISO 8601 and the box's zone is
  given where local days matter (ADR-179); money is integer cents with an
  ISO 4217 currency.
  """

  # -- schemas

  def uuid, do: %{"type" => "string", "format" => "uuid"}
  def nullable(schema), do: Map.put(schema, "type", [schema["type"], "null"])
  def date_time, do: %{"type" => "string", "format" => "date-time"}

  def page(item) do
    %{
      "type" => "object",
      "properties" => %{
        "data" => %{"type" => "array", "items" => item},
        "next_cursor" => %{
          "type" => ["string", "null"],
          "description" => "Pass as `cursor` for the next page; null on the last one."
        }
      },
      "required" => ["data", "next_cursor"]
    }
  end

  def page_input(extra \\ %{}, required \\ []) do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" =>
        Map.merge(
          %{
            "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 50, "default" => 25},
            "cursor" => %{"type" => "string", "maxLength" => 40}
          },
          extra
        ),
      "required" => required
    }
  end

  def member_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => uuid(),
        "display_name" => %{"type" => "string"},
        "email" =>
          nullable(%{
            "type" => "string",
            "description" => "Only for keys of staff who may see members' contact details."
          }),
        "roles" => %{"type" => "array", "items" => %{"type" => "string"}},
        "joined_at" => nullable(date_time())
      },
      "required" => ["display_name", "email", "id", "joined_at", "roles"]
    }
  end

  def class_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => uuid(),
        "name" => %{"type" => "string"},
        "starts_at" => date_time(),
        "duration_minutes" => %{"type" => "integer"},
        "location_id" => nullable(uuid()),
        "coach_id" => nullable(uuid()),
        "capacity" => nullable(%{"type" => "integer"}),
        "booked" => %{"type" => "integer"},
        "status" => %{
          "type" => "string",
          "enum" => ["scheduled", "cancelled"],
          "x-enum-descriptions" => %{
            "scheduled" => "The class takes place.",
            "cancelled" => "The box cancelled it; its bookings were released."
          }
        }
      },
      "required" => [
        "booked",
        "capacity",
        "coach_id",
        "duration_minutes",
        "id",
        "location_id",
        "name",
        "starts_at",
        "status"
      ]
    }
  end

  def booking_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => uuid(),
        "class_id" => uuid(),
        "member_id" => nullable(uuid()),
        "status" => %{
          "type" => "string",
          "description" =>
            "pending (waits for staff), approved, waitlisted, rejected, withdrawn (cancelled), timed_out."
        },
        "guest" => %{"type" => "boolean"},
        "created_at" => nullable(date_time())
      },
      "required" => ["class_id", "created_at", "guest", "id", "member_id", "status"]
    }
  end

  def package_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => uuid(),
        "name" => %{"type" => "string"},
        "type" => nullable(%{"type" => "string"}),
        "price_cents" => nullable(%{"type" => "integer"}),
        "currency" => %{"type" => "string"},
        "billing_period" => nullable(%{"type" => "string"}),
        "active" => %{"type" => "boolean"}
      },
      "required" => ["active", "billing_period", "currency", "id", "name", "price_cents", "type"]
    }
  end

  def payment_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => uuid(),
        "member_id" => nullable(uuid()),
        "amount_cents" => %{"type" => "integer"},
        "refunded_cents" => %{"type" => "integer"},
        "currency" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "purpose" => nullable(%{"type" => "string"}),
        "created_at" => nullable(date_time()),
        "paid_at" => nullable(date_time())
      },
      "required" => [
        "amount_cents",
        "created_at",
        "currency",
        "id",
        "member_id",
        "paid_at",
        "purpose",
        "refunded_cents",
        "status"
      ]
    }
  end

  # -- views

  def member(account, roles, email?) do
    %{
      "id" => account.id,
      "display_name" => Map.get(account, :nickname) || Map.get(account, :handle),
      "email" => if(email?, do: Map.get(account, :email)),
      "roles" => Enum.map(roles || [], &to_string/1),
      "joined_at" => iso(Map.get(account, :joined_at) || Map.get(account, :inserted_at))
    }
  end

  def class(slot) do
    bookings = Map.get(slot, :bookings)

    booked =
      Map.get(slot, :booked_count) ||
        (is_list(bookings) && Enum.count(bookings, &(to_string(&1.status) == "approved"))) || 0

    %{
      "id" => slot.id,
      "name" => class_name(slot),
      "starts_at" => iso(slot.scheduled_at),
      "duration_minutes" => slot.duration_minutes,
      "location_id" => Map.get(slot, :location_id),
      "coach_id" => Map.get(slot, :coach_user_id),
      "capacity" => Map.get(slot, :capacity),
      "booked" => booked,
      "status" => if(Map.get(slot, :cancelled_at), do: "cancelled", else: "scheduled")
    }
  end

  def booking(booking, class_id \\ nil) do
    %{
      "id" => booking.id,
      "class_id" => class_id || Map.get(booking, :scheduled_class_id),
      "member_id" => Map.get(booking, :user_id),
      "status" => to_string(booking.status),
      "guest" => is_binary(Map.get(booking, :guest_name)),
      "created_at" => iso(Map.get(booking, :inserted_at))
    }
  end

  def package(package, currency) do
    %{
      "id" => package.id,
      "name" => package.name,
      "type" => package |> Map.get(:package_type) |> string(),
      "price_cents" => Map.get(package, :base_price_cents),
      "currency" => Map.get(package, :currency) || currency,
      "billing_period" => package |> Map.get(:billing_period) |> string(),
      "active" => Map.get(package, :active, true) != false and is_nil(Map.get(package, :retired_at))
    }
  end

  def payment(intent) do
    %{
      "id" => intent.id,
      "member_id" => Map.get(intent, :user_id),
      "amount_cents" => Map.get(intent, :amount_cents),
      "refunded_cents" => Map.get(intent, :refunded_cents) || 0,
      "currency" => Map.get(intent, :currency),
      "status" => intent |> Map.get(:status) |> string(),
      "purpose" => intent |> Map.get(:purpose_type) |> string(),
      "created_at" => iso(Map.get(intent, :created_at) || Map.get(intent, :inserted_at)),
      "paid_at" => iso(Map.get(intent, :succeeded_at))
    }
  end

  def class_name(slot) do
    case Map.get(slot, :class_type) do
      %{name: name} when is_binary(name) -> name
      _none -> Map.get(slot, :name)
    end
  end

  # -- cursors (opaque to clients; an offset today)

  def decode_cursor(nil), do: {:ok, 0}

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, "o:" <> offset} <- Base.url_decode64(cursor, padding: false),
         {value, ""} when value >= 0 <- Integer.parse(offset) do
      {:ok, value}
    else
      _invalid -> {:error, {:invalid_fields, %{"cursor" => ["is not valid"]}}}
    end
  end

  def next_cursor(offset, limit, total) when offset + limit < total,
    do: Base.url_encode64("o:#{offset + limit}", padding: false)

  def next_cursor(_offset, _limit, _total), do: nil

  def iso(nil), do: nil
  def iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
  def iso(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  def iso(value) when is_binary(value), do: value

  defp string(nil), do: nil
  defp string(value), do: to_string(value)
end
