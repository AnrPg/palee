defmodule Palee.ContentTranslations.Domain.Subjects do
  @moduledoc """
  ADR-500: the closed catalog of texts a business writes that can be
  translated, as `subject_kind => %{field => max length of a translation}`.

  A translation may run longer than its source (German, Russian), so each
  limit is about one and a half times the source field's own limit. A new
  translatable text is one line here plus the source that lists it.
  """

  @subjects %{
    "box_profile" => %{"about" => 4_000},
    "site_faq" => %{"question" => 300, "answer" => 1_500},
    "package" => %{"name" => 200, "description" => 3_000},
    "class_type" => %{"name" => 120},
    "event" => %{"title" => 200},
    "space" => %{"name" => 120, "description" => 3_000},
    "location" => %{"name" => 120}
  }

  @type kind :: String.t()
  @type field :: String.t()

  @doc "Every subject kind."
  @spec kinds() :: [kind()]
  def kinds, do: @subjects |> Map.keys() |> Enum.sort()

  @doc "The translatable fields of a kind."
  @spec fields(kind()) :: [field()]
  def fields(kind), do: @subjects |> Map.get(kind, %{}) |> Map.keys() |> Enum.sort()

  @doc "Whether `field` of `kind` can be translated."
  @spec known?(term(), term()) :: boolean()
  def known?(kind, field) when is_binary(kind) and is_binary(field),
    do: @subjects |> Map.get(kind, %{}) |> Map.has_key?(field)

  def known?(_kind, _field), do: false

  @doc "The longest translation of `field` of `kind`."
  @spec max_length(kind(), field()) :: pos_integer()
  def max_length(kind, field), do: @subjects |> Map.fetch!(kind) |> Map.fetch!(field)
end
