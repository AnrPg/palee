defmodule Palee.Llm do
  @moduledoc """
  Model calls behind one port (ADR-360): `Palee.Llm.Ports.LlmProvider`,
  with the Gemini adapter as the default and a deterministic sandbox for
  dev and tests. Which adapter serves a feature is configuration:

      config :palee, :llm_provider, Palee.Infrastructure.Llm.GeminiLlmProvider
      # optional per-feature routing
      config :palee, :llm_routes, %{"help_desk" => Palee.Infrastructure.Llm.SandboxLlmProvider}

  The tool loop (`run_tools/4`), the cost limits (`Budget`) and the
  data-is-not-instructions cleaning (`Untrusted`) live here so every AI
  feature, and the v4 agents (ADR-301), share them.
  """

  alias Palee.Llm.Domain.{Budget, Request, Response, Tool, ToolLoop, Untrusted}

  @doc "One model call through the provider configured for `options.metering.feature`."
  def generate(%Request{} = request, options \\ %{}) do
    provider(feature(options)).generate(request, options)
  end

  @doc """
  The tool loop over the configured provider: `execute` runs one tool call
  (`fn name, args, step -> {:ok, content, audit} | {:error, code} end`).
  """
  def run_tools(%Request{} = request, execute, options \\ %{}, loop_opts \\ []) do
    ToolLoop.run(request, &generate(&1, options), execute, loop_opts)
  end

  @doc "The provider module for a feature (routing, else the default)."
  def provider(feature \\ nil) do
    routes = Application.get_env(:palee, :llm_routes, %{})

    Map.get(routes, to_string(feature)) || Application.fetch_env!(:palee, :llm_provider)
  end

  defdelegate tool(attrs), to: Tool, as: :new
  defdelegate decode_json(response), to: Response, as: :json
  defdelegate budget_limits(config), to: Budget, as: :limits
  defdelegate check_budget(limits, usage), to: Budget, as: :check
  defdelegate budget_windows(now), to: Budget, as: :windows
  defdelegate budget_remaining(limits, spent), to: Budget, as: :remaining
  defdelegate untrusted_text(value, max), to: Untrusted, as: :text
  defdelegate untrusted_data(value, max), to: Untrusted, as: :data
  defdelegate data_rule(), to: Untrusted, as: :rule

  @doc "The configured limits of one AI feature (`:ai_features` config)."
  def feature_limits(feature) when is_atom(feature) do
    :palee |> Application.get_env(:ai_features, []) |> Keyword.get(feature, []) |> Budget.limits()
  end

  defp feature(%{metering: %{feature: feature}}), do: feature
  defp feature(_options), do: nil
end
