defmodule Palee.Operations.Operation do
  @moduledoc """
  One use case exposed to people, integrations and (in v4) agents: the
  behaviour of ADR-300's operation registry. This is its first step
  (ADR-378): the public API v1 is made of these modules, and its routes,
  OpenAPI document, input validation and scope checks all come from
  `spec/0`, so nothing restates a schema.

  `spec/0` returns a map:

    * `name` (`"bookings.create"`), `version` (1), `kind` (`:query` |
      `:command`), `summary` and `description` written for the integrator
      (and later an agent: when to use it, when not);
    * `input` and `output`: JSON Schema 2020-12 maps (string keys); path
      and query parameters are input properties;
    * `capability`: ADR-099 capabilities, any of which suffices, checked
      against the acting person's current rights;
    * `scope`: the API key scope (ADR-378) it needs;
    * `risk`: `:read | :write_reversible | :write_irreversible | :outward |
      :money`; `data_classes`: `[:personal | :health | :financial |
      :user_generated]` (ADR-300);
    * `http`: `%{method: :get | :post | :delete, path: "/bookings/{id}",
      status: 200}` for REST;
    * `examples`: `[%{input: map, output: map}]`.

  `execute/2` calls only application services or a context's public API
  (ADR-043). Every command implements `preview/2`, a dry run that writes
  nothing (ADR-300 §4); the contract test refuses a command without one.
  """

  @type context :: map()
  @type result :: {:ok, map()} | {:error, term()} | {:error, term(), map()}

  @callback spec() :: map()
  @callback execute(context(), input :: map()) :: result()
  @callback preview(context(), input :: map()) :: result()

  @optional_callbacks preview: 2
end
