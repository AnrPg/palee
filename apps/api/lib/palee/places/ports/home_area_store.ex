defmodule Palee.Places.Ports.HomeAreaStore do
  @moduledoc "A person's «Η περιοχή μου» (ADR-154); every call is the context user's own."

  @callback list(context :: map()) :: [map()]
  @doc "The country (ISO alpha-2) of the main neighbourhood, or nil (ADR-421)."
  @callback country(context :: map()) :: String.t() | nil
  @callback replace(context :: map(), neighbourhood_ids :: [binary()], DateTime.t()) ::
              :ok | {:error, term()}
end
