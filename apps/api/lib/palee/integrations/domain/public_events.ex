defmodule Palee.Integrations.Domain.PublicEvents do
  @moduledoc """
  The events a box's webhooks and Zapier/Make triggers can receive
  (ADR-379), made from Palee's domain events (ADR-144).

  Events are **thin**: they carry ids, the kind of change and the few facts
  a receiver filters on, never names, emails or notes. A receiver that needs
  more reads the object through the public API with its own scoped key, so
  a webhook URL that leaks gives away nothing personal (data minimisation,
  GDPR art. 5(1)(c)). Each type needs the read scope of its object to be
  subscribed to through the API.

  The envelope is versioned with `api_version`; adding fields is not a
  breaking change, renaming or removing one is (a new version).
  """

  @api_version "2026-11-01"

  @types [
    %{
      type: "member.activated",
      scope: "members:read",
      source: :membership_activated,
      en: "A person became an active member",
      el: "Ένα άτομο έγινε ενεργό μέλος"
    },
    %{
      type: "booking.created",
      scope: "bookings:read",
      source: :booking_made,
      en: "A member booked a class",
      el: "Ένα μέλος έκλεισε θέση σε τμήμα"
    },
    %{
      type: "booking.cancelled",
      scope: "bookings:read",
      source: :booking_cancelled,
      en: "A booking was cancelled",
      el: "Μια κράτηση ακυρώθηκε"
    },
    %{
      type: "class.cancelled",
      scope: "classes:read",
      source: :class_cancelled,
      en: "A class was cancelled",
      el: "Ένα τμήμα ακυρώθηκε"
    },
    %{
      type: "attendance.recorded",
      scope: "bookings:read",
      source: :attendance_recorded,
      en: "A member came to a class",
      el: "Ένα μέλος ήρθε σε τμήμα"
    },
    %{
      type: "payment.recorded",
      scope: "payments:read",
      source: :membership_payment_recorded,
      en: "A package payment was recorded",
      el: "Καταγράφηκε πληρωμή πακέτου"
    }
  ]

  @ping "ping"

  def api_version, do: @api_version
  def catalog, do: @types
  def types, do: Enum.map(@types, & &1.type)
  def ping_type, do: @ping

  @doc "The domain event names that have a public event."
  def sources, do: Enum.map(@types, & &1.source)

  @doc "The scope a type needs, or nil for an unknown type."
  def scope_for(type), do: Enum.find_value(@types, &(&1.type == type && &1.scope))

  @doc "Sorted unique known types, or `{:error, :invalid_events}`."
  def normalize(types) when is_list(types) do
    types = types |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()

    if types != [] and Enum.all?(types, &(&1 in types())),
      do: {:ok, types},
      else: {:error, :invalid_events}
  end

  def normalize(_types), do: {:error, :invalid_events}

  @doc """
  `{:ok, type, data}` for a domain event that has a public form, or
  `:ignore`. `data` holds ids and plain facts only.
  """
  def from_domain(:membership_activated, %{user_id: user_id}),
    do: {:ok, "member.activated", %{member_id: user_id}}

  def from_domain(:booking_made, %{booking_id: booking_id} = payload),
    do:
      {:ok, "booking.created",
       %{booking_id: booking_id, class_id: payload[:scheduled_class_id], member_id: payload[:user_id]}}

  def from_domain(:booking_cancelled, %{booking_id: booking_id} = payload) do
    {:ok, "booking.cancelled",
     %{
       booking_id: booking_id,
       class_id: payload[:scheduled_class_id],
       member_id: payload[:user_id],
       cancelled_by: by(payload[:by])
     }}
  end

  def from_domain(:class_cancelled, %{scheduled_class_id: class_id}),
    do: {:ok, "class.cancelled", %{class_id: class_id}}

  def from_domain(:attendance_recorded, %{user_id: user_id} = payload) do
    {:ok, "attendance.recorded",
     %{
       class_id: payload[:scheduled_class_id],
       booking_id: payload[:booking_id],
       member_id: user_id,
       status: payload[:status] && to_string(payload[:status])
     }}
  end

  def from_domain(:membership_payment_recorded, %{payment_id: payment_id} = payload) do
    {:ok, "payment.recorded",
     %{
       payment_id: payment_id,
       member_id: payload[:user_id],
       amount_cents: payload[:amount_cents]
     }}
  end

  def from_domain(_name, _payload), do: :ignore

  @doc "The envelope sent to receivers."
  def envelope(event_id, type, data, organization_id, %DateTime{} = at) do
    %{
      id: event_id,
      type: type,
      api_version: @api_version,
      created_at: DateTime.to_iso8601(at),
      box_id: organization_id,
      data: data
    }
  end

  @doc "When the domain event happened, or `now`."
  def occurred_at(%{at: %DateTime{} = at}, _now), do: at
  def occurred_at(_payload, now), do: now

  defp by(by) when by in [:member, :staff, :system], do: to_string(by)
  defp by(by) when is_binary(by), do: by
  defp by(_by), do: nil
end
