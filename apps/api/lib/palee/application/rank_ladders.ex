defmodule Palee.Application.RankLadders do
  @moduledoc """
  Staff › Ρυθμίσεις › «Βαθμοί» (ADR-377): the box's ladders of belts and
  levels. A ladder starts from a template («Πρότυπα») or from scratch;
  its discipline is a workout type (ADR-275) and a rank may suggest one
  of the box's scale levels (ADR-128).
  """

  alias Palee.Application.{Clock, RankStanding}
  alias Palee.{Localization, Ranks, Workouts}

  # Templates were Greek before ADR-400; a client that names no language
  # still gets them in Greek.
  @default_locale "el"
  @locales ~w(en el ar ru de es pt-PT he it bg nl fr)

  def list(context, params \\ %{}) do
    ladders = Ranks.with_context(context, fn -> Ranks.list_ladders() end)

    {:ok,
     %{
       ladders: Enum.map(ladders, &RankStanding.present_ladder/1),
       templates: templates(locale(params)),
       colors: Ranks.colors()
     }}
  end

  @doc "The template catalogue in one of the web's languages (ADR-400)."
  def templates(locale) do
    translate = &Localization.translate(locale, &1, &2, "rank_templates")
    Enum.map(Ranks.templates(), &Ranks.localize_template(&1, translate))
  end

  def create(%{organization_id: organization_id} = context, params) do
    params = expand_template(params)

    with {:ok, attrs} <- ladder_attrs(params),
         {:ok, ranks} <- Ranks.cast_ranks(get(params, "ranks"), scale_levels(context)) do
      ranks = Enum.map(ranks, &Map.put(&1, :id, nil))

      context
      |> Ranks.with_context(fn ->
        Ranks.insert_ladder(Map.put(attrs, :organization_id, organization_id), ranks)
      end)
      |> present()
    end
  end

  def update(%{organization_id: organization_id} = context, id, params) do
    with {:ok, attrs} <- ladder_attrs(params),
         {:ok, ranks} <- Ranks.cast_ranks(get(params, "ranks"), scale_levels(context)) do
      context
      |> Ranks.with_context(fn ->
        case Ranks.get_ladder(id) do
          nil ->
            {:error, :not_found}

          ladder ->
            Ranks.update_ladder(ladder, Map.put(attrs, :organization_id, organization_id), ranks)
        end
      end)
      |> present()
    end
  end

  def archive(context, id) do
    Ranks.with_context(context, fn ->
      case Ranks.get_ladder(id) do
        nil -> {:error, :not_found}
        ladder -> with {:ok, _archived} <- Ranks.archive_ladder(ladder, Clock.now()), do: :ok
      end
    end)
  end

  defp present({:ok, ladder}), do: {:ok, RankStanding.present_ladder(ladder)}
  defp present(error), do: error

  defp expand_template(params) do
    case get(params, "template") do
      nil ->
        params

      key ->
        case Ranks.template(key) do
          nil ->
            params

          template ->
            template =
              Ranks.localize_template(
                template,
                &Localization.translate(locale(params), &1, &2, "rank_templates")
              )

            params
            |> params_map()
            |> Map.put_new("name", template.name)
            |> Map.put_new("discipline", template.discipline)
            |> Map.put_new("style", template.style)
            |> Map.put_new("ranks", template.ranks)
        end
    end
  end

  defp locale(params) do
    case get(params, "locale") do
      locale when locale in @locales -> locale
      _other -> @default_locale
    end
  end

  defp ladder_attrs(params) do
    {:ok,
     %{
       name: get(params, "name"),
       discipline: get(params, "discipline"),
       style: get(params, "style") || "belt",
       class_type_ids: get(params, "class_type_ids") || [],
       position: get(params, "position") || 0
     }}
  end

  defp scale_levels(context) do
    case Workouts.list_scale_levels(context) do
      {:ok, levels} -> Enum.map(levels, & &1.slug)
      levels when is_list(levels) -> Enum.map(levels, & &1.slug)
      _other -> []
    end
  end

  defp params_map(params) when is_struct(params), do: params |> Map.from_struct() |> params_map()

  defp params_map(params) when is_map(params),
    do: Map.new(params, fn {k, v} -> {to_string(k), v} end)

  defp get(params, key), do: Map.get(params_map(params), key)
end
