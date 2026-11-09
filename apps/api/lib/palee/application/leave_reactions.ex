defmodule Palee.Application.LeaveReactions do
  @moduledoc """
  ADR-595: someone who left a box and joins it again (by the join link, a
  package bought on its page, an accepted request, an invitation or staff)
  stops leaving on the finance side too, whichever way they came back. The
  box side was already cleared by the join itself.
  """

  @behaviour Palee.DomainEvents.Handler

  alias Palee.Application.MembershipRenewal

  @impl true
  def handle_event(:membership_activated, %{organization_id: org, user_id: user})
      when is_binary(org) and is_binary(user) do
    case MembershipRenewal.rejoined(org, user) do
      {:ok, _membership} -> :ok
      {:error, _reason} -> :ok
    end
  end

  def handle_event(_name, _payload), do: :ok
end
