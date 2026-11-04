defmodule Palee.Programmes.Domain.ProgrammeCover do
  @moduledoc """
  ADR-541: a programme's cover photo, pure.

  The coach uploads a photo and edits it in the browser (crop to the cover
  aspect, rotate by 90°, zoom, brightness); the browser renders the result
  and uploads it too. The programme keeps both uploads and the edit, so
  editing again starts from the original:

    * `media_id`: the rendered cover, shown everywhere (`cover_url`);
    * `original_media_id`: the photo as uploaded (the rendered one when the
      coach did not edit);
    * `edit`: `%{"rotation" => 0 | 90 | 180 | 270, "zoom" => 1.0..4.0,
      "brightness" => 0.5..1.5, "crop" => %{"x", "y", "width", "height"}}`,
      the crop in fractions (0..1) of the original **after** rotation.

  The cover is #{16}:#{9}: the rendered image and the crop (in the original's
  pixels) must be within 2% of it. No cover means the theme colour strip.
  """

  @aspect 16 / 9
  @tolerance 0.02
  @rotations [0, 90, 180, 270]
  @min_zoom 1.0
  @max_zoom 4.0
  @min_edge 320

  def aspect, do: "16:9"
  def rotations, do: @rotations
  def min_edge, do: @min_edge

  @doc """
  Normalises the edit params: `{:ok, edit}` or
  `{:error, :invalid_cover_edit}`. Missing params take their neutral value
  (no rotation, zoom 1, brightness 1, the whole image).
  """
  def normalize_edit(nil), do: {:ok, neutral()}

  def normalize_edit(edit) when is_map(edit) do
    rotation = value(edit, "rotation", 0)
    zoom = value(edit, "zoom", 1)
    brightness = value(edit, "brightness", 1)
    crop = value(edit, "crop", %{"x" => 0, "y" => 0, "width" => 1, "height" => 1})

    with true <- rotation in @rotations,
         true <- is_number(zoom) and zoom >= @min_zoom and zoom <= @max_zoom,
         true <- is_number(brightness) and brightness >= 0.5 and brightness <= 1.5,
         {:ok, crop} <- crop(crop) do
      {:ok,
       %{
         "rotation" => rotation,
         "zoom" => zoom / 1,
         "brightness" => brightness / 1,
         "crop" => crop
       }}
    else
      _invalid -> {:error, :invalid_cover_edit}
    end
  end

  def normalize_edit(_edit), do: {:error, :invalid_cover_edit}

  defp neutral do
    %{
      "rotation" => 0,
      "zoom" => 1.0,
      "brightness" => 1.0,
      "crop" => %{"x" => 0.0, "y" => 0.0, "width" => 1.0, "height" => 1.0}
    }
  end

  defp crop(crop) when is_map(crop) do
    [x, y, w, h] = Enum.map(~w(x y width height), &value(crop, &1, nil))

    if Enum.all?([x, y, w, h], &is_number/1) and x >= 0 and y >= 0 and w > 0 and h > 0 and
         x + w <= 1.0001 and y + h <= 1.0001,
       do: {:ok, %{"x" => x / 1, "y" => y / 1, "width" => w / 1, "height" => h / 1}},
       else: :error
  end

  defp crop(_crop), do: :error

  @atoms %{
    "rotation" => :rotation,
    "zoom" => :zoom,
    "brightness" => :brightness,
    "crop" => :crop,
    "x" => :x,
    "y" => :y,
    "width" => :width,
    "height" => :height
  }

  defp value(map, key, default) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Map.fetch!(@atoms, key), default)
    end
  end

  @doc """
  Checks the rendered cover (`width`, `height` in pixels) and, when the
  original's size is known, that the crop has the cover's aspect:
  `:ok` or `{:error, :invalid_cover_size}`.
  """
  def check_size(rendered, original, edit) do
    cond do
      not sized?(rendered) -> {:error, :invalid_cover_size}
      min(rendered.width, rendered.height) < @min_edge * 9 / 16 -> {:error, :invalid_cover_size}
      not aspect?(rendered.width, rendered.height) -> {:error, :invalid_cover_size}
      sized?(original) and not crop_aspect?(original, edit) -> {:error, :invalid_cover_size}
      true -> :ok
    end
  end

  defp sized?(%{width: w, height: h}) when is_integer(w) and is_integer(h) and w > 0 and h > 0,
    do: true

  defp sized?(_media), do: false

  defp aspect?(width, height), do: abs(width / height / @aspect - 1) <= @tolerance

  defp crop_aspect?(original, %{"rotation" => rotation, "crop" => crop}) do
    {w, h} =
      if rotation in [90, 270],
        do: {original.height, original.width},
        else: {original.width, original.height}

    aspect?(crop["width"] * w, crop["height"] * h)
  end
end
