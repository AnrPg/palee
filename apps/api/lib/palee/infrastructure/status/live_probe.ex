defmodule Palee.Infrastructure.Status.LiveProbe do
  @moduledoc """
  ADR-364: probes every status page component.

  * `app` – the readiness checks behind `/api/health` (database, Redis,
    Oban): the worst of the three.
  * `search`, `files` – the same readiness checks for Meilisearch and
    object storage.
  * `email` – the outbox (ADR-203/212): `degraded` while mail is deferred
    past the daily budget, `down` once the SMTP key has expired.
  * `payments`, `fiscal` – reachability of the providers' APIs from
    `config :palee, :status_probe_targets` (`[%{component, name, url}]`):
    any HTTP answer below 500 means reachable (401 is fine: no credentials
    are sent); 5xx is `degraded`; no answer is `down`. With several
    providers, all down is `down`, some down is `degraded`. A component
    without targets is not reported (the page shows it as unknown).

  HTTP calls use Req with `config :palee, :status_http, req_options: [...]`
  (tests plug `Req.Test`).
  """

  @behaviour Palee.Status.Ports.DependencyProbe

  alias Palee.Infrastructure.Readiness

  @timeout 3_000

  @impl true
  def check do
    readiness =
      case Readiness.status() do
        {_ok_or_error, checks} -> checks
      end

    [
      %{
        component: "app",
        status: worst_of(Enum.map([:database, :redis, :jobs], &readiness_status(readiness, &1))),
        reason: reasons(readiness, [:database, :redis, :jobs])
      },
      %{
        component: "search",
        status: readiness_status(readiness, :search),
        reason: reasons(readiness, [:search])
      },
      %{
        component: "files",
        status: readiness_status(readiness, :object_storage),
        reason: reasons(readiness, [:object_storage])
      },
      email()
    ] ++ http_components()
  end

  defp readiness_status(checks, key) do
    case Map.get(checks, key) do
      :ok -> "operational"
      %{status: :ok} -> "operational"
      nil -> "operational"
      _error -> "down"
    end
  end

  defp reasons(checks, keys) do
    keys
    |> Enum.flat_map(fn key ->
      case Map.get(checks, key) do
        %{reason: reason} -> ["#{key}: #{reason}"]
        _ok -> []
      end
    end)
    |> case do
      [] -> nil
      list -> Enum.join(list, "; ")
    end
  end

  defp email do
    stats = Palee.Email.sending_stats()
    key = Palee.Email.smtp_key_status(Date.utc_today())

    cond do
      key.state == :expired ->
        %{component: "email", status: "down", reason: "SMTP key expired"}

      stats.deferred > 0 ->
        %{
          component: "email",
          status: "degraded",
          reason: "#{stats.deferred} emails deferred past the daily budget"
        }

      true ->
        %{component: "email", status: "operational", reason: nil}
    end
  rescue
    error -> %{component: "email", status: "down", reason: Exception.message(error)}
  end

  defp http_components do
    :palee
    |> Application.get_env(:status_probe_targets, [])
    |> Enum.group_by(& &1.component)
    |> Enum.map(fn {component, targets} ->
      results =
        targets
        |> Task.async_stream(&probe/1, timeout: @timeout * 2, on_timeout: :kill_task)
        |> Enum.zip(targets)
        |> Enum.map(fn
          {{:ok, result}, target} -> {target.name, result}
          {{:exit, _reason}, target} -> {target.name, {"down", "timeout"}}
        end)

      %{
        component: component,
        status: combine(Enum.map(results, fn {_name, {status, _reason}} -> status end)),
        reason:
          results
          |> Enum.reject(fn {_name, {status, _reason}} -> status == "operational" end)
          |> Enum.map_join("; ", fn {name, {_status, reason}} -> "#{name}: #{reason}" end)
          |> blank_to_nil()
      }
    end)
  end

  defp probe(%{url: url}) do
    options =
      Keyword.merge(
        [receive_timeout: @timeout, connect_options: [timeout: @timeout], retry: false],
        :palee |> Application.get_env(:status_http, []) |> Keyword.get(:req_options, [])
      )

    case Req.get(url, options) do
      {:ok, %Req.Response{status: status}} when status < 500 -> {"operational", nil}
      {:ok, %Req.Response{status: status}} -> {"degraded", "HTTP #{status}"}
      {:error, error} -> {"down", error |> Exception.message() |> String.slice(0, 120)}
    end
  end

  defp combine(statuses) do
    cond do
      statuses != [] and Enum.all?(statuses, &(&1 == "down")) -> "down"
      Enum.any?(statuses, &(&1 in ["down", "degraded"])) -> "degraded"
      true -> "operational"
    end
  end

  defp worst_of(statuses) do
    Enum.reduce(statuses, "operational", &Palee.Status.Domain.Components.worst/2)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text
end
