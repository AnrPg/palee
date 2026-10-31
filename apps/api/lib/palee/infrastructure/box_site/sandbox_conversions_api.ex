defmodule Palee.Infrastructure.BoxSite.SandboxConversionsApi do
  @moduledoc "ADR-354: the Conversions API for dev and test; accepts every event and sends nothing."

  @behaviour Palee.BoxSite.Ports.ConversionsApi

  @impl true
  def send_event(_pixel_id, _token, %{"event_name" => "Lead"}), do: :ok
  def send_event(_pixel_id, _token, _event), do: {:error, {:rejected, :unknown_event}}
end
