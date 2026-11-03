defmodule Palee.Application.Operations.Runner do
  @moduledoc """
  Runs a registered operation (ADR-300, ADR-378) the same way for every
  caller:

    1. **Policy.** The acting person's current rights must include one of
       the spec's capabilities (ADR-099); an API key must also hold the
       spec's scope. Rights are read now, on every call (ADR-301): a staff
       member who loses a role takes their keys' rights with them.
    2. **Input.** The spec's JSON Schema validates and casts it.
    3. **Idempotency.** A command with an `Idempotency-Key` runs once; the
       same key and body get the first answer again (ADR-300 §5).
    4. **Execute** (or **preview**: a dry run that writes nothing).

  Answers `{:ok, status, body}` or an error the transport maps.
  """

  alias Palee.{Integrations, Operations, Organizations}

  @type opts :: [
          idempotency_key: String.t() | nil,
          preview: boolean(),
          now: DateTime.t()
        ]

  def run(context, name, raw_input, opts \\ []) do
    with {:ok, module, spec} <- Operations.fetch(name),
         :ok <- authorize(context, spec),
         {:ok, input} <- Operations.cast_input(spec, raw_input) do
      cond do
        Keyword.get(opts, :preview, false) -> preview(module, spec, context, input)
        spec.kind == :command -> once(module, spec, context, input, opts)
        true -> execute(module, spec, context, input)
      end
    end
  end

  @doc "Whether `context` may run `spec` (scope and capability)."
  def authorize(context, spec) do
    cond do
      not scope_allows?(context, spec.scope) -> {:error, :insufficient_scope}
      not Enum.any?(spec.capability, &Organizations.can?(context, &1)) -> {:error, :forbidden}
      true -> :ok
    end
  end

  defp scope_allows?(_context, "any"), do: true
  defp scope_allows?(%{principal: %{kind: :api_key, scopes: scopes}}, scope), do: scope in scopes
  defp scope_allows?(_context, _scope), do: true

  defp preview(module, spec, context, input) do
    if spec.kind == :command and function_exported?(module, :preview, 2) do
      with {:ok, body} <- module.preview(context, input), do: {:ok, 200, %{preview: body}}
    else
      {:error, :preview_unsupported}
    end
  end

  defp execute(module, spec, context, input) do
    case module.execute(context, input) do
      {:ok, body} -> {:ok, Map.get(spec.http, :status, 200), body}
      {:error, _reason} = error -> error
      {:error, reason, details} -> {:error, reason, details}
    end
  end

  defp once(module, spec, context, input, opts) do
    case {Keyword.get(opts, :idempotency_key), principal_key(context)} do
      {nil, _principal} ->
        execute(module, spec, context, input)

      {_key, nil} ->
        execute(module, spec, context, input)

      {key, principal} ->
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

        case Integrations.begin_idempotent(context, principal, key, spec.name, input, now) do
          {:ok, record_id} -> remember(context, record_id, execute(module, spec, context, input))
          {:replay, status, body} -> {:ok, status, body, :replayed}
          {:error, _reason} = error -> error
        end
    end
  end

  # Only answers worth repeating are kept; a refusal frees the key, so the
  # client can fix the request and send it again under the same key.
  defp remember(context, record_id, {:ok, status, body} = result) do
    Integrations.complete_idempotent(context, record_id, status, json_safe(body))
    result
  end

  defp remember(context, record_id, error) do
    Integrations.abandon_idempotent(context, record_id)
    error
  end

  defp principal_key(%{principal: %{kind: :api_key, api_key_id: id}}), do: "api_key:" <> id
  defp principal_key(%{user_id: user_id}) when is_binary(user_id), do: "user:" <> user_id
  defp principal_key(_context), do: nil

  # The stored answer is what JSON would carry.
  defp json_safe(body), do: body |> Jason.encode!() |> Jason.decode!()
end
