defmodule Palee.Application.Programmes.Covers do
  @moduledoc """
  ADR-541: a programme's cover photo, on the media pipeline (ADR-148).

  The coach uploads the photo as `programme_cover` media (presigned PUT,
  then «complete», which inspects it), edits it in the browser and uploads
  the rendered cover the same way. `set/3` puts both on the programme with
  the edit; the previous ones are released unless another programme still
  shows them. `remove/2` goes back to the theme colour strip.

  Covers are public media: their URLs are stable, for the programme page,
  the catalogue and the box website.
  """

  alias Palee.Application.{MediaStorage, MediaUrls, ReleaseMedia}
  alias Palee.{Media, Programmes}

  @purpose "programme_cover"

  def purpose, do: @purpose

  @doc """
  Sets the cover: `params` `media_id` (the rendered cover),
  `original_media_id` (optional: the photo it was made from, default the
  same) and `edit` (`ProgrammeCover.normalize_edit/1`).
  """
  def set(context, programme, params) do
    rendered_id = params[:media_id]
    original_id = params[:original_media_id] || rendered_id

    with {:ok, edit} <- Programmes.normalize_cover_edit(stringify(params[:edit])),
         {:ok, media} <- ready(context, Enum.uniq([rendered_id, original_id])),
         rendered = Map.fetch!(media, rendered_id),
         original = Map.fetch!(media, original_id),
         :ok <-
           Programmes.check_cover_size(
             rendered,
             if(original_id == rendered_id, do: nil, else: original),
             edit
           ),
         {:ok, updated} <-
           Programmes.set_cover(context, programme, %{
             cover_media_id: rendered_id,
             cover_original_media_id: original_id,
             cover_edit: edit,
             updated_by_id: context.user_id
           }) do
      _ = Media.set_attached(context, :tenant, Enum.uniq([rendered_id, original_id]), now())
      release(context, programme, [rendered_id, original_id])
      {:ok, updated}
    end
  end

  @doc "Removes the cover (the theme colour strip shows again)."
  def remove(context, programme) do
    with {:ok, updated} <-
           Programmes.set_cover(context, programme, %{
             cover_media_id: nil,
             cover_original_media_id: nil,
             cover_edit: nil,
             updated_by_id: context.user_id
           }) do
      release(context, programme, [])
      {:ok, updated}
    end
  end

  defp ready(context, ids) do
    if Enum.all?(ids, &uuid?/1) do
      with {:ok, media} <- Media.fetch_ready(context, @purpose, ids),
           do: {:ok, Map.new(media, &{&1.id, &1})}
    else
      {:error, :invalid_media}
    end
  end

  defp uuid?(id), do: is_binary(id) and match?({:ok, _}, Ecto.UUID.cast(id))

  # The media the programme no longer shows go, unless another programme
  # (a duplicate) still shows them.
  defp release(context, programme, kept) do
    gone =
      [programme.cover_media_id, programme.cover_original_media_id]
      |> Enum.reject(&(is_nil(&1) or &1 in kept))
      |> Enum.uniq()

    unless gone == [] or Programmes.cover_in_use?(context, gone, programme.id),
      do: ReleaseMedia.call(context, :tenant, gone)

    :ok
  end

  @doc """
  `%{programme_id => %{url, original_url}}` for programmes of one business.
  """
  def urls(_context, []), do: %{}

  def urls(context, programmes) do
    ids =
      programmes
      |> Enum.flat_map(&[&1.cover_media_id, Map.get(&1, :cover_original_media_id)])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    shown =
      case ids do
        [] ->
          %{}

        ids ->
          context
          |> Media.list(:tenant, ids)
          |> Enum.filter(&(&1.status == "ready" and &1.purpose == @purpose))
          |> Map.new(&{&1.id, MediaUrls.present(context, &1).url})
      end

    Map.new(programmes, fn programme ->
      {programme.id,
       %{
         url: Map.get(shown, programme.cover_media_id),
         original_url: Map.get(shown, Map.get(programme, :cover_original_media_id))
       }}
    end)
  end

  @doc "The staff view of a programme's cover, or nil."
  def staff(_programme, nil), do: nil
  def staff(%{cover_media_id: nil}, _urls), do: nil

  def staff(programme, urls) do
    %{
      media_id: programme.cover_media_id,
      url: urls.url,
      original_media_id: programme.cover_original_media_id,
      original_url: urls.original_url,
      edit: programme.cover_edit,
      aspect: Programmes.cover_aspect()
    }
  end

  @doc "A catalogue row's cover URL from its object key (public bucket)."
  def catalogue_url(_organization_id, nil), do: nil

  def catalogue_url(organization_id, key) do
    case MediaStorage.read_url({:tenant, organization_id}, :media_public, key) do
      {:ok, url} -> url
      {:error, _reason} -> nil
    end
  end

  defp stringify(nil), do: nil

  defp stringify(%{} = map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  defp stringify(value), do: value

  defp now, do: DateTime.utc_now()
end
