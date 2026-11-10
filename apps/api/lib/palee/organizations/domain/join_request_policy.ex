defmodule Palee.Organizations.Domain.JoinRequestPolicy do
  @moduledoc """
  ADR-552: how someone who is not a box member becomes one without the
  member join link. Pure rules; callers pass the facts.

    * **Buying.** A box that lists a package to everyone (sold online, or
      «Το θέλω» at the desk) has already said yes to whoever buys it, so
      starting to buy it makes the person a box member (`admission/2` with
      `:purchase`). A former member (suspended or revoked) is not let back
      in by buying: the box decided that, so they ask instead.
    * **Asking.** Anyone else asks («Ζήτα να γίνεις μέλος»); the box's staff
      accept (`:accepted_request`, which also lets a former member back in)
      or decline. One open request per person and box.
  """

  @statuses ~w(requested accepted declined cancelled)
  @closed ~w(accepted declined cancelled)

  def statuses, do: @statuses
  def closed_statuses, do: @closed

  @doc "Whether a request in `status` still waits for the box."
  def open?(status), do: status == "requested"

  @doc """
  What to do with the person's membership row (`nil` when they never had
  one) when they are admitted for `reason` (`:purchase` or
  `:accepted_request`).
  """
  def admission(nil, _reason), do: :create
  # ADR-595: someone who left the box comes back by any way in, on their own.
  def admission(%{status: :active, left_at: %DateTime{}}, _reason), do: :create
  def admission(%{status: :active}, _reason), do: :already_member
  def admission(_former, :accepted_request), do: :create
  def admission(_former, :purchase), do: {:error, :membership_unavailable}

  @doc """
  Whether the person may ask: never while they are a box member
  (`standing` from `Organizations.membership_standing/2`).
  """
  def can_ask?(:member), do: {:error, :already_member}
  def can_ask?(_standing), do: :ok

  @doc """
  ADR-638: where the viewer stands with a box, for «Γίνε μέλος» beside
  «Ακολούθησε»: `"staff"` or `"member"` (the box's current member, so no
  button), `"requested"` (their request waits) or `"none"` (they may join).
  `staff?` and `member?` come from the person's current memberships.
  """
  def viewer_status(staff?, member?, requested?)
  def viewer_status(true, _member?, _requested?), do: "staff"
  def viewer_status(_staff?, true, _requested?), do: "member"
  def viewer_status(_staff?, _member?, true), do: "requested"
  def viewer_status(_staff?, _member?, _requested?), do: "none"

  @doc "ADR-638: every `viewer_status/3` value."
  def viewer_statuses, do: ~w(none requested member staff)

  @doc "The status a staff decision closes a request with."
  def decision("accept"), do: {:ok, "accepted"}
  def decision("decline"), do: {:ok, "declined"}
  def decision(_other), do: {:error, :invalid_join_request_decision}
end
