defmodule Palee.HelpCentre.Domain.ArticlePolicy do
  @moduledoc """
  Rules of help articles (ADR-362), pure.

    * An article is identified by `slug` and exists once per locale; a
      reader asking for a locale it is not written in gets the English one,
      marked `fallback: true`.
    * `screens` are app route patterns the article is linked from
      (`/admin/shop`, `/admin/users/:id`); a screen path matches a pattern
      when every segment matches (`:name` matches any one segment) and the
      path may continue below it.
    * `guide_id` names the in-app guide (ADR-193) the article can start.
    * Bodies are Markdown limited to headings, lists, emphasis and links;
      raw HTML is refused, so the web renders them without sanitising
      surprises.
  """

  @locales ~w(en el ar ru de es pt-PT he it bg nl fr)
  @statuses ~w(draft published)
  @audiences ~w(staff member all)
  @fallback_locale "en"
  @slug ~r/^[a-z0-9][a-z0-9-]{1,79}$/
  @guide ~r/^[a-z][a-z0-9_]{1,47}$/
  @screen ~r/^\/[A-Za-z0-9_\-\/:\[\]]{0,199}$/
  @html ~r/<\s*\/?\s*[a-zA-Z!]/

  def locales, do: @locales
  def statuses, do: @statuses
  def audiences, do: @audiences
  def fallback_locale, do: @fallback_locale

  @doc "The supported locale for `value`, else the fallback."
  def locale(value) when value in @locales, do: value

  def locale(value) when is_binary(value) do
    down = value |> String.trim() |> String.replace("_", "-") |> String.downcase()

    Enum.find(@locales, fn locale ->
      String.downcase(locale) == down or String.downcase(locale) == hd(String.split(down, "-"))
    end) || @fallback_locale
  end

  def locale(_value), do: @fallback_locale

  @doc """
  Validates a write from the Palee team. `params` may hold `title`,
  `summary`, `body`, `audience`, `feature_key`, `guide_id`, `screens`,
  `keywords`, `status` and `position`. Returns `{:ok, attrs}` with
  `published_at` set on first publication, or `{:error, {:invalid_fields, map}}`.
  """
  def write_attrs(existing, params, actor_id, %DateTime{} = now) when is_map(params) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)
    current = existing || %{}

    attrs =
      %{
        title: text(params, "title", current, :title),
        summary: text(params, "summary", current, :summary),
        body: text(params, "body", current, :body) || "",
        audience: Map.get(params, "audience", Map.get(current, :audience, "staff")),
        feature_key: optional(params, "feature_key", current, :feature_key),
        guide_id: optional(params, "guide_id", current, :guide_id),
        screens: list(params, "screens", current, :screens),
        keywords: list(params, "keywords", current, :keywords),
        status: Map.get(params, "status", Map.get(current, :status, "draft")),
        position: Map.get(params, "position", Map.get(current, :position, 100)),
        source: "palee",
        complete: true,
        updated_by_id: actor_id,
        version: Map.get(current, :version, 0) + 1
      }

    case errors(attrs) do
      empty when map_size(empty) == 0 ->
        published_at =
          Map.get(current, :published_at) || if(attrs.status == "published", do: now)

        {:ok, Map.put(attrs, :published_at, published_at)}

      errors ->
        {:error, {:invalid_fields, errors}}
    end
  end

  def write_attrs(_existing, _params, _actor_id, _now), do: {:error, :bad_request}

  defp errors(attrs) do
    [
      {:title, present?(attrs.title) and String.length(attrs.title) <= 160},
      {:summary, present?(attrs.summary) and String.length(attrs.summary) <= 500},
      {:body,
       is_binary(attrs.body) and String.length(attrs.body) <= 20_000 and
         not Regex.match?(@html, attrs.body)},
      {:audience, attrs.audience in @audiences},
      {:status, attrs.status in @statuses},
      {:guide_id, is_nil(attrs.guide_id) or Regex.match?(@guide, attrs.guide_id)},
      {:feature_key, is_nil(attrs.feature_key) or Regex.match?(@guide, attrs.feature_key)},
      {:screens, valid_list?(attrs.screens, 20, &Regex.match?(@screen, &1))},
      {:keywords, valid_list?(attrs.keywords, 30, &(String.length(&1) in 1..60))},
      {:position, is_integer(attrs.position) and attrs.position in 0..10_000}
    ]
    |> Enum.reject(fn {_field, ok?} -> ok? end)
    |> Map.new(fn {field, _ok} -> {field, ["invalid"]} end)
  end

  def valid_slug?(slug), do: is_binary(slug) and Regex.match?(@slug, slug)

  @doc "Whether the screen `path` (query string ignored) matches the route `pattern`."
  def screen_matches?(pattern, path) when is_binary(pattern) and is_binary(path) do
    pattern_segments = segments(pattern)
    path_segments = path |> String.split("?") |> hd() |> segments()

    length(path_segments) >= length(pattern_segments) and
      pattern_segments
      |> Enum.zip(path_segments)
      |> Enum.all?(fn {expected, actual} ->
        String.starts_with?(expected, ":") or String.starts_with?(expected, "[") or
          expected == actual
      end)
  end

  def screen_matches?(_pattern, _path), do: false

  @doc "Whether an article is linked from the screen `path`."
  def on_screen?(%{screens: screens}, path) when is_list(screens),
    do: Enum.any?(screens, &screen_matches?(&1, path))

  def on_screen?(_article, _path), do: false

  @doc """
  One article per slug for `locale`: the locale's own row when it exists,
  else the English one marked `fallback: true`.
  """
  def localize(rows, locale) do
    rows
    |> Enum.group_by(& &1.slug)
    |> Enum.flat_map(fn {_slug, versions} ->
      case Enum.find(versions, &(&1.locale == locale)) ||
             Enum.find(versions, &(&1.locale == @fallback_locale)) do
        nil -> []
        row -> [Map.put(row, :fallback, row.locale != locale)]
      end
    end)
  end

  @doc "Whether a reader of `audience` (staff, member) sees the article."
  def for_audience?(_article, nil), do: true
  def for_audience?(%{audience: "all"}, _reader), do: true
  def for_audience?(%{audience: audience}, reader), do: audience == reader

  @doc "What the API shows of an article."
  def public(article) do
    %{
      slug: article.slug,
      locale: article.locale,
      title: article.title,
      summary: article.summary,
      body: article.body,
      audience: article.audience,
      feature_key: article.feature_key,
      guide_id: article.guide_id,
      screens: article.screens || [],
      complete: Map.get(article, :complete, true),
      fallback: Map.get(article, :fallback, false),
      updated_at: Map.get(article, :updated_at)
    }
  end

  @doc "What the Palee team's console shows (drafts and authoring fields too)."
  def console(article) do
    article
    |> public()
    |> Map.merge(%{
      id: article.id,
      status: article.status,
      source: article.source,
      version: article.version,
      keywords: article.keywords || [],
      position: article.position,
      published_at: article.published_at
    })
  end

  defp segments(path), do: String.split(path, "/", trim: true)

  defp text(params, key, current, field) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) -> String.trim(value)
      {:ok, _other} -> nil
      :error -> Map.get(current, field)
    end
  end

  defp optional(params, key, current, field) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) ->
        if String.trim(value) == "", do: nil, else: String.trim(value)

      {:ok, nil} ->
        nil

      {:ok, other} ->
        other

      :error ->
        Map.get(current, field)
    end
  end

  defp list(params, key, current, field) do
    case Map.fetch(params, key) do
      {:ok, values} when is_list(values) ->
        values |> Enum.map(&if(is_binary(&1), do: String.trim(&1), else: &1)) |> Enum.uniq()

      {:ok, other} ->
        other

      :error ->
        Map.get(current, field) || []
    end
  end

  defp valid_list?(values, max, valid?) when is_list(values),
    do: length(values) <= max and Enum.all?(values, &(is_binary(&1) and valid?.(&1)))

  defp valid_list?(_values, _max, _valid?), do: false

  defp present?(value), do: is_binary(value) and value != ""
end
