defmodule Palee.Integrations.Domain.Scopes do
  @moduledoc """
  What a public API key may do (ADR-378). A scope names an object and
  `read` or `write`; `write` never implies `read`. A key's rights are, on
  every call, the intersection of its scopes and the current rights of the
  staff member it acts for (ADR-301), so a scope can only narrow.

  Payments are read-only by design: money moves only through Palee's own
  checkout and the desk (ADR-246).
  """

  @catalog [
    %{
      scope: "members:read",
      en: "Read members (name, contact, roles)",
      el: "Ανάγνωση μελών (όνομα, επικοινωνία, ρόλοι)"
    },
    %{
      scope: "members:write",
      en: "Invite people as members",
      el: "Πρόσκληση ατόμων ως μέλη"
    },
    %{
      scope: "classes:read",
      en: "Read the schedule of classes",
      el: "Ανάγνωση του προγράμματος τμημάτων"
    },
    %{
      scope: "classes:write",
      en: "Add classes to the schedule",
      el: "Προσθήκη τμημάτων στο πρόγραμμα"
    },
    %{
      scope: "bookings:read",
      en: "Read bookings",
      el: "Ανάγνωση κρατήσεων"
    },
    %{
      scope: "bookings:write",
      en: "Book members into classes and cancel bookings",
      el: "Κράτηση θέσης για μέλη και ακύρωση κρατήσεων"
    },
    %{
      scope: "packages:read",
      en: "Read packages and members' packages",
      el: "Ανάγνωση πακέτων"
    },
    %{
      scope: "packages:write",
      en: "Give a member a package",
      el: "Ανάθεση πακέτου σε μέλος"
    },
    %{
      scope: "payments:read",
      en: "Read payments (never change them)",
      el: "Ανάγνωση πληρωμών (χωρίς αλλαγές)"
    },
    %{
      scope: "webhooks:write",
      en: "Subscribe to events (Zapier, Make)",
      el: "Εγγραφή σε γεγονότα (Zapier, Make)"
    }
  ]

  @scopes Enum.map(@catalog, & &1.scope)

  def catalog, do: @catalog
  def all, do: @scopes

  @doc "Sorted, unique, known scopes, or `{:error, :invalid_scopes}`."
  def normalize(scopes) when is_list(scopes) do
    scopes = scopes |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()

    if scopes != [] and Enum.all?(scopes, &(&1 in @scopes)),
      do: {:ok, scopes},
      else: {:error, :invalid_scopes}
  end

  def normalize(_scopes), do: {:error, :invalid_scopes}

  def allows?(scopes, scope) when is_list(scopes), do: scope in scopes
  def allows?(_scopes, _scope), do: false
end
