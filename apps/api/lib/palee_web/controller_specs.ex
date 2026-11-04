defmodule PaleeWeb.ControllerSpecs do
  @moduledoc """
  `OpenApiSpex.ControllerSpecs` with a leaner `operation/2`.

  The library's `operation/2` (3.22.x) defines each clause as
  `def open_api_operation(action), do: @spec_attributes[action]`. Reading the
  accumulating attribute inside the function body bakes the whole list of
  operations declared so far into every clause as a literal, so a controller
  with N operations carries N growing copies of it (N² literals). Across the
  API that came to ~210 MB of literals, ~430 MB of resident memory at boot,
  enough to OOM-kill the release under its 1 GiB limit after v3.1.

  Here each spec is computed once into a plain attribute and only that one
  operation is baked into its clause. The specs themselves, the accumulated
  `@spec_attributes`, `shared_tags/0` and `shared_security/0` are unchanged,
  so the exported OpenAPI document is identical.
  """

  # The library's __using__, with this module's operation/2 and an honest
  # @spec: an action without a spec falls back to the library's warning clause
  # (:ok), and `operation :action, false` gives nil. The library's own spec
  # (Operation.t() only) held because `@spec_attributes[action]` typed as any
  # term; with the operation baked in, dialyzer sees the real return types.
  defmacro __using__(_opts) do
    quote do
      import OpenApiSpex.ControllerSpecs, except: [operation: 2]
      import PaleeWeb.ControllerSpecs, only: [operation: 2]

      Module.register_attribute(__MODULE__, :spec_attributes, accumulate: true)
      Module.register_attribute(__MODULE__, :shared_tags, accumulate: true)
      Module.register_attribute(__MODULE__, :shared_security, accumulate: true)

      @before_compile {OpenApiSpex.ControllerSpecs, :before_compile}

      @spec open_api_operation(atom()) :: OpenApiSpex.Operation.t() | nil | :ok
    end
  end

  @doc "Defines the Operation spec for a controller action; see `OpenApiSpex.ControllerSpecs.operation/2`."
  defmacro operation(action, spec) do
    spec = Macro.postwalk(spec, &expand_alias(&1, __CALLER__))

    quote do
      @palee_open_api_operation OpenApiSpex.ControllerSpecs.operation_spec(
                                  __MODULE__,
                                  unquote(action),
                                  unquote(spec)
                                )
      @spec_attributes {unquote(action), @palee_open_api_operation}

      def open_api_operation(unquote(action)), do: @palee_open_api_operation
    end
  end

  # Same as the library's private helper: aliases in the spec resolve in the
  # caller, without being tracked as compile-time dependencies.
  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:__attr__, 3}})

  defp expand_alias(other, _env), do: other
end
