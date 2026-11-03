defmodule Palee.Infrastructure.Nutrition.ChainFoodDatabase do
  @moduledoc """
  The food database port as a chain of free sources (ADR-421), asked in
  order until one has the barcode: Open Food Facts, USDA FoodData Central
  (only with a key), then the licensed product lists (the Greek source).
  Palee's own store (the person's own foods, then the cache) is asked before
  the chain by `Application.Foods`, so this module only sees cache misses.

  Every source runs with its own timeout, inside a total budget, so a scan
  never hangs: a source still running when its time (or the budget) is up
  is stopped and counts as a transient failure.

    * the first `{:ok, attrs}` wins (each cached row comes from one source);
    * a source switched off (`:not_configured`) is skipped;
    * nobody has it → `{:error, :not_found}`, but only when every source
      answered: a transient failure anywhere means "try again later", so the
      outbox retries rather than believing a miss for 7 days.

  Config (`:food_chain`): `sources` (`[{module, timeout_ms}]`) and
  `total_timeout_ms`.
  """

  @behaviour Palee.Nutrition.Ports.FoodDatabase

  @impl true
  def lookup(barcode, language) do
    config = Application.get_env(:palee, :food_chain, [])

    lookup(barcode, language,
      sources: Keyword.fetch!(config, :sources),
      total_timeout_ms: Keyword.fetch!(config, :total_timeout_ms)
    )
  end

  @doc "The chain with explicit `sources` and `total_timeout_ms` (tests)."
  def lookup(barcode, language, opts) do
    deadline = now() + Keyword.fetch!(opts, :total_timeout_ms)
    ask(Keyword.fetch!(opts, :sources), barcode, language, deadline, [])
  end

  defp ask([], _barcode, _language, _deadline, []), do: {:error, :not_found}

  defp ask([], _barcode, _language, _deadline, failures),
    do: {:error, {:transient, {:sources, Enum.reverse(failures)}}}

  defp ask([{source, timeout} | rest], barcode, language, deadline, failures) do
    case min(timeout, deadline - now()) do
      left when left <= 0 ->
        skipped =
          Enum.map([{source, timeout} | rest], fn {module, _} -> {name(module), :budget} end)

        {:error, {:transient, {:sources, Enum.reverse(failures) ++ skipped}}}

      left ->
        case run(source, barcode, language, left) do
          {:ok, attrs} ->
            {:ok, attrs}

          {:error, :not_found} ->
            ask(rest, barcode, language, deadline, failures)

          {:error, :not_configured} ->
            ask(rest, barcode, language, deadline, failures)

          {:error, reason} ->
            ask(rest, barcode, language, deadline, [{name(source), reason} | failures])
        end
    end
  end

  defp run(source, barcode, language, timeout) do
    task = Task.async(fn -> safely(source, barcode, language) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %{} = attrs}} -> {:ok, attrs}
      {:ok, {:error, _reason} = error} -> error
      {:ok, other} -> {:error, {:unexpected, other}}
      nil -> {:error, :timeout}
    end
  end

  # A source that raises must not take the scan (the caller is linked) down.
  defp safely(source, barcode, language) do
    source.lookup(barcode, language)
  rescue
    exception -> {:error, {:crashed, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:crashed, {kind, reason}}}
  end

  defp name(module), do: module |> Module.split() |> List.last()

  defp now, do: System.monotonic_time(:millisecond)
end
