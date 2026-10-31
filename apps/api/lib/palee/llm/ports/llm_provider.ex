defmodule Palee.Llm.Ports.LlmProvider do
  @moduledoc """
  The one port every model call goes through (ADR-360; ADR-301 §6 names it
  `Agents.Ports.LlmProvider` for v4, and this is that port).

  `options`:

    * `:metering` – the caller's metering context (`operation_id`,
      `feature`, `organization_id`, `user_id`); the adapter reports every
      billed call to `Palee.AiUsage` with it (ADR-152);
    * `:agent` – a short name of the calling agent, for metering and logs.

  Errors: `:llm_not_configured` (no key), `:llm_quota_exhausted` (the
  provider's credits or rate limit), `:llm_unavailable` (anything else).
  An adapter never raises for a provider failure.
  """

  alias Palee.Llm.Domain.{Request, Response}

  @type error :: :llm_not_configured | :llm_quota_exhausted | :llm_unavailable

  @callback generate(Request.t(), options :: map()) :: {:ok, Response.t()} | {:error, error()}
end
