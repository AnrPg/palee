defmodule Palee.Application.DiplomaSignatures do
  @moduledoc """
  «Υπογραφή για διπλώματα» (ADR-377 addendum, option Γ): a coach's own
  signature image, drawn on the diplomas of the promotions they award.

    * The person alone sees, replaces and removes it (`GET|PUT|DELETE
      /api/me/diploma-signature`, the preview through `.../image`). Nobody
      else ever receives it except drawn inside a diploma PDF.
    * Stored privately (the private media bucket, the person's own prefix
      `users/<id>/diploma-signature/`), never behind a public URL.
    * Every set and removal is recorded in `diploma_signature_events`.
    * Snapshot: an award keeps the id of the signature current when it was
      made (`rank_awards.signature_id`), so a later replacement does not
      change a diploma already issued. Replacing retires the old row and
      keeps its image for those diplomas; removing deletes every version,
      so every diploma drawn afterwards shows an empty line.
    * Account deletion deletes rows and objects (`purge_person/1`); the
      person's data export carries the rows and the images
      (`export_files/1`).
  """

  require Logger

  alias Palee.Application.{Clock, MediaStorage}
  alias Palee.{Organizations, Pdf}
  alias Palee.Ranks.Domain.SignaturePolicy
  alias Palee.Ranks.SignatureStore

  @bucket :media_private

  @doc "What the settings section shows: whether the person signs diplomas, the signature and the limits."
  def show(%{user_id: user_id} = scope) do
    {:ok,
     %{
       eligible: eligible?(user_id),
       signature: scope |> SignatureStore.current(user_id) |> view(),
       limits: limits()
     }}
  end

  @doc "Stores a new signature (`image_base64`, PNG or JPEG) and retires the current one."
  def put(%{user_id: user_id} = scope, params, now \\ Clock.now()) do
    with :ok <- authorize(user_id),
         {:ok, bytes} <- decode(params),
         {:ok, meta} <- SignaturePolicy.validate(bytes) do
      id = Ecto.UUID.generate()
      key = SignaturePolicy.object_key(user_id, id, meta.content_type)
      owner = owner(user_id)

      with :ok <- store(owner, key, bytes, meta.content_type) do
        case SignatureStore.replace(
               scope,
               user_id,
               Map.merge(meta, %{id: id, object_key: key}),
               now
             ) do
          {:ok, signature} ->
            {:ok, %{signature: view(signature)}}

          {:error, _reason} = error ->
            _deleted = MediaStorage.delete(owner, [%{bucket: @bucket, key: key}])
            error
        end
      end
    end
  end

  @doc "The person's own current image, for the preview."
  def image(%{user_id: user_id} = scope) do
    case SignatureStore.current(scope, user_id) do
      nil ->
        {:error, :not_found}

      signature ->
        case read(signature) do
          {:ok, bytes} -> {:ok, %{content_type: signature.content_type, data: bytes}}
          :error -> {:error, :storage_unavailable}
        end
    end
  end

  @doc "Removes every version of the person's signature, rows and images."
  def remove(%{user_id: user_id} = scope, now \\ Clock.now()) do
    {:ok, removed} = SignatureStore.remove(scope, user_id, now)
    delete_objects(user_id, removed)
    :ok
  end

  @doc "Id of the person's current signature (the snapshot an award keeps), or nil."
  def current_id(user_id) when is_binary(user_id) do
    case SignatureStore.current(%{user_id: user_id}, user_id) do
      %{id: id} -> id
      nil -> nil
    end
  end

  def current_id(_user_id), do: nil

  @doc """
  The signature `id` as a PDF image, read as the system (the diploma is
  drawn for the coach or for the person promoted); nil when it is gone or
  cannot be read.
  """
  def pdf_image(nil), do: nil

  def pdf_image(id) when is_binary(id) do
    with %{} = signature <- SignatureStore.get(:system, id),
         {:ok, bytes} <- read(signature),
         {:ok, image} <- Pdf.Image.parse(bytes) do
      image
    else
      _missing -> nil
    end
  end

  @doc "Account deletion (ADR-211): every row and object of the person."
  def purge_person(user_id) when is_binary(user_id) do
    {:ok, removed} = SignatureStore.remove(:system, user_id, Clock.now())
    delete_objects(user_id, removed)
    :ok
  end

  @doc "The person's data export (ADR-267): each stored image as `{file name, bytes}`."
  def export_files(user_id) when is_binary(user_id) do
    %{user_id: user_id}
    |> SignatureStore.list(user_id)
    |> Enum.flat_map(fn signature ->
      case read(signature) do
        {:ok, bytes} -> [{"diploma-signature/" <> Path.basename(signature.object_key), bytes}]
        :error -> []
      end
    end)
  end

  @doc "The limits the settings section shows."
  def limits do
    {min_w, min_h} = SignaturePolicy.min_dimensions()
    {max_w, max_h} = SignaturePolicy.max_dimensions()

    %{
      max_bytes: SignaturePolicy.max_bytes(),
      content_types: SignaturePolicy.content_types(),
      min_width: min_w,
      min_height: min_h,
      max_width: max_w,
      max_height: max_h
    }
  end

  # -- helpers -------------------------------------------------------------------

  defp eligible?(user_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.any?(fn %{membership: membership} ->
      SignaturePolicy.can_sign?([membership.role | membership.roles || []])
    end)
  end

  defp authorize(user_id), do: if(eligible?(user_id), do: :ok, else: {:error, :forbidden})

  defp decode(params) do
    case value(params, :image_base64) do
      text when is_binary(text) ->
        case Base.decode64(strip_data_url(text), ignore: :whitespace) do
          {:ok, bytes} -> {:ok, bytes}
          :error -> {:error, :invalid_signature_image}
        end

      _missing ->
        {:error, :invalid_signature_image}
    end
  end

  defp strip_data_url("data:" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [_header, data] -> data
      _other -> rest
    end
  end

  defp strip_data_url(text), do: text

  defp value(params, key) when is_map(params),
    do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp value(_params, _key), do: nil

  defp owner(user_id), do: {:account, user_id}

  defp store(owner, key, bytes, content_type) do
    case MediaStorage.put(owner, @bucket, key, bytes, content_type) do
      :ok ->
        :ok

      {:ok, _stored} ->
        :ok

      {:error, reason} ->
        Logger.warning("diploma_signature_store_failed reason=#{inspect(reason)}")
        {:error, :storage_unavailable}
    end
  end

  defp read(%{user_id: user_id, object_key: key}) do
    if SignaturePolicy.owned_key?(user_id, key) do
      path =
        Path.join(System.tmp_dir!(), "palee-signature-#{System.unique_integer([:positive])}")

      try do
        with :ok <- MediaStorage.download(owner(user_id), @bucket, key, path),
             {:ok, bytes} <- File.read(path) do
          {:ok, bytes}
        else
          _error -> :error
        end
      after
        File.rm(path)
      end
    else
      :error
    end
  end

  defp delete_objects(_user_id, []), do: :ok

  defp delete_objects(user_id, signatures) do
    objects =
      for %{object_key: key} <- signatures,
          SignaturePolicy.owned_key?(user_id, key),
          do: %{bucket: @bucket, key: key}

    case MediaStorage.delete(owner(user_id), objects) do
      {:ok, _count} ->
        :ok

      {:error, reason} ->
        Logger.warning("diploma_signature_delete_failed reason=#{inspect(reason)}")
        :ok
    end
  end

  defp view(nil), do: nil

  defp view(signature) do
    %{
      id: signature.id,
      content_type: signature.content_type,
      byte_size: signature.byte_size,
      width: signature.width,
      height: signature.height,
      updated_at: signature.inserted_at
    }
  end
end
