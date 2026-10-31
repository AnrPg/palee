defmodule Palee.TestSupport.FakeReviewSignals do
  @moduledoc "ADR-355 tests: review ask facts from `:fake_review_signals` (defaults: a regular)."

  @behaviour Palee.ReviewAsks.Ports.ReviewSignals

  @impl true
  def facts(_context, _user_id) do
    Map.merge(
      %{
        active_membership: true,
        member_since: DateTime.add(DateTime.utc_now(), -90 * 86_400, :second),
        attendance_count: 10,
        last_attended_at: DateTime.utc_now()
      },
      Application.get_env(:palee, :fake_review_signals, %{})
    )
  end
end
