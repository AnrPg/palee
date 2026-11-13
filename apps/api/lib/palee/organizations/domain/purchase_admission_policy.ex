defmodule Palee.Organizations.Domain.PurchaseAdmissionPolicy do
  @moduledoc """
  ADR-642: when buying a package makes someone a box member (ANR 2026-11-13,
  «Με ενεργό πακέτο»). Pure rules over a membership row.

    * **Starting to buy** (`ADR-552` «Συνέχεια»): the person gets no role
      anyone sees. The row is stored as `:guest` marked
      `purchase_admission_at` only so the box's checkout and «Το θέλω» work
      for them; it is no member and no «Επισκέπτης» (no club, no member app,
      no guest banner, «Γίνε μέλος» still shows) and the box's staff lookups
      leave it out (migration `20271114100000`).
    * **«Το θέλω»** (`on_request/2`): sending it makes a guest a member,
      still marked, so they see the classes and book their one class while
      the request waits (ADR-633).
    * **A package starts** (`on_package/1`): online payment, the desk's
      «Είσπραξη» or «Εκκρεμεί πληρωμή». A marked guest becomes a member;
      the mark goes.
    * **A request closes with no package** (`on_request_closed/2`): cancelled,
      declined or lapsed, with nothing else waiting and no package ever. A
      marked member goes back to that hidden row (they can try again any time).

  Staff never move this way, and anyone who joined another way (join link,
  invitation, accepted join request, staff) carries no mark.
  """

  alias Palee.Organizations.Domain.MembershipPolicy

  @doc "The row a purchase admission creates (`now` is when they started to buy)."
  def admitted(now), do: %{role: :guest, roles: [:guest], purchase_admission_at: now}

  @doc """
  «Το θέλω» was sent: `{:promote, attrs}` for a guest of the box (a desk
  guest too: they asked to become a member), else `:keep`.
  """
  def on_request(%{roles: roles} = membership, now) do
    if MembershipPolicy.guest_only?(roles),
      do:
        {:promote, %{roles: [:member], purchase_admission_at: membership_mark(membership) || now}},
      else: :keep
  end

  def on_request(_membership, _now), do: :keep

  @doc """
  A package started: a marked guest becomes a member and the mark goes; a
  marked member just loses the mark. Unmarked rows (desk guests sold a
  package by staff, ADR-272) stay as they are.
  """
  def on_package(%{purchase_admission_at: %DateTime{}, roles: roles}) do
    if MembershipPolicy.guest_only?(roles),
      do: {:promote, %{roles: [:member], purchase_admission_at: nil}},
      else: {:settle, %{purchase_admission_at: nil}}
  end

  def on_package(_membership), do: :keep

  @doc """
  A request closed with no package. `kept?` is whether anything still holds
  the membership (another request waiting, or a Finance profile: a package
  now or before). A marked member who kept nothing goes back to the hidden
  row (no role anyone sees).
  """
  def on_request_closed(%{purchase_admission_at: %DateTime{}, roles: roles}, false) do
    if MembershipPolicy.client?(roles) and not MembershipPolicy.staff?(roles),
      do: {:demote, %{roles: [:guest]}},
      else: :keep
  end

  def on_request_closed(_membership, _kept?), do: :keep

  @doc "Whether the row is a purchase admission that has not reached a package."
  def marked?(%{purchase_admission_at: %DateTime{}}), do: true
  def marked?(_membership), do: false

  defp membership_mark(%{purchase_admission_at: at}), do: at
  defp membership_mark(_membership), do: nil
end
