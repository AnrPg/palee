defmodule Palee.Application.RankLadders do
  @moduledoc """
  Staff › Ρυθμίσεις › «Βαθμοί» (ADR-377): the box's ladders of belts and
  levels. A ladder starts from a template («Πρότυπα») or from scratch;
  its discipline is a workout type (ADR-275) and a rank may suggest one
  of the box's scale levels (ADR-128).
  """

  alias Palee.Application.{Clock, RankStanding}
  alias Palee.{Localization, Organizations, Ranks, Workouts}

  # Templates were Greek before ADR-400; a client that names no language
  # still gets them in Greek.
  @default_locale "el"
  @locales ~w(en el ar ru de es pt-PT he it bg nl fr)

  @doc """
  Who keeps the ladders (ADR-400 follow-up): the owner and admins
  (`manage_settings`, a solo coach owns their business) and a head coach
  (`manage_coaching` over every client); not a coach of their own clients.
  """
  def authorize(context) do
    cond do
      Organizations.capability_scope(context, :manage_settings) -> :ok
      Organizations.capability_scope(context, :manage_coaching) == :all -> :ok
      true -> {:error, :forbidden}
    end
  end

  def list(context, params \\ %{}) do
    with :ok <- authorize(context), do: do_list(context, params)
  end

  defp do_list(context, params) do
    ladders = Ranks.with_context(context, fn -> Ranks.list_ladders() end)

    {:ok,
     %{
       ladders: Enum.map(ladders, &RankStanding.present_ladder/1),
       templates: templates(locale(params)),
       colors: Ranks.colors(),
       box_disciplines: box_disciplines(context)
     }}
  end

  # The training kinds of the box's public profile (ADR-275 keys), which the
  # template picker shows first.
  defp box_disciplines(context) do
    case Organizations.get_public_profile(context) do
      %{disciplines: disciplines} when is_list(disciplines) -> disciplines
      _none -> []
    end
  end

  @doc "The template catalogue in one of the web's languages (ADR-400)."
  def templates(locale) do
    translate = &Localization.translate(locale, &1, &2, "rank_templates")
    Enum.map(Ranks.templates(), &Ranks.localize_template(&1, translate))
  end

  def create(%{organization_id: organization_id} = context, params) do
    params = expand_template(params)

    with :ok <- authorize(context),
         {:ok, attrs} <- ladder_attrs(params, ["classes", "days"]),
         {:ok, ranks} <- Ranks.cast_ranks(get(params, "ranks"), scale_levels(context)) do
      ranks = ranks |> Enum.map(&Map.put(&1, :id, nil)) |> Ranks.assign_skill_ids([])

      context
      |> Ranks.with_context(fn ->
        Ranks.insert_ladder(Map.put(attrs, :organization_id, organization_id), ranks)
      end)
      |> present()
    end
  end

  def update(%{organization_id: organization_id} = context, id, params) do
    with :ok <- authorize(context),
         {:ok, ranks} <- Ranks.cast_ranks(get(params, "ranks"), scale_levels(context)) do
      context
      |> Ranks.with_context(fn ->
        with %{} = ladder <- Ranks.get_ladder(id) || {:error, :not_found},
             {:ok, attrs} <- ladder_attrs(params, ladder.ready_criteria) do
          # Skills keep their ids (and so their ticks) when renamed or moved.
          ranks = Ranks.assign_skill_ids(ranks, ladder.ranks)
          Ranks.update_ladder(ladder, Map.put(attrs, :organization_id, organization_id), ranks)
        end
      end)
      |> present()
    end
  end

  def archive(context, id) do
    with :ok <- authorize(context), do: do_archive(context, id)
  end

  defp do_archive(context, id) do
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
            |> Map.put_new("ready_criteria", template.ready)
        end
    end
  end

  defp locale(params) do
    case get(params, "locale") do
      locale when locale in @locales -> locale
      _other -> @default_locale
    end
  end

  defp ladder_attrs(params, default_criteria) do
    with {:ok, criteria} <-
           Ranks.cast_ready_criteria(get(params, "ready_criteria"), default_criteria) do
      {:ok,
       %{
         name: get(params, "name"),
         discipline: get(params, "discipline"),
         style: get(params, "style") || "belt",
         class_type_ids: get(params, "class_type_ids") || [],
         position: get(params, "position") || 0,
         ready_criteria: criteria
       }}
    end
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
