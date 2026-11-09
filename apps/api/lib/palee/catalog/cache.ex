defmodule Palee.Catalog.Cache do
  @moduledoc """
  ADR-560: loads the reference catalog copy at boot and polls the stored
  revision every `:reference_catalog_poll_ms` (off when `nil`), so a change
  made on one pod reaches every pod without clustering.
  """

  use GenServer

  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Palee.Catalog.refresh()
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    case Palee.Catalog.refresh_if_stale() do
      {:error, reason} ->
        Logger.warning("reference catalog: revision check failed: #{inspect(reason)}")

      _ok ->
        :ok
    end

    schedule()
    {:noreply, state}
  end

  defp schedule do
    case Application.get_env(:palee, :reference_catalog_poll_ms) do
      ms when is_integer(ms) and ms > 0 -> Process.send_after(self(), :poll, ms)
      _off -> :ok
    end
  end
end
