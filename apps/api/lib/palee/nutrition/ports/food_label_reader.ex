defmodule Palee.Nutrition.Ports.FoodLabelReader do
  @moduledoc """
  Reads a food's label from photos (ADR-421, «Φωτογραφία ετικέτας»): the
  front and the nutrition table. Returns what the model read, unchecked
  (`Nutrition.Domain.FoodLabel` checks it). Only the photos and a fixed
  instruction are sent, never who sent them; nothing is stored.
  """

  @type image :: %{bytes: binary(), content_type: String.t()}

  @typedoc "Who the call is made for, so its model usage is metered (ADR-152)."
  @type metering :: %{
          optional(:organization_id) => String.t() | nil,
          optional(:user_id) => String.t() | nil,
          optional(:operation_id) => String.t(),
          optional(:feature) => String.t()
        }

  @doc "Whether label reading can run on this server (a model key is set)."
  @callback available?() :: boolean()

  @callback read([image()], %{locale: String.t()}, metering()) ::
              {:ok, map()} | {:error, :not_configured} | {:error, term()}
end
