defmodule Palee.Ranks.Domain.SignaturePolicy do
  @moduledoc """
  Rules for a coach's diploma signature (ADR-377 addendum, option Γ).

    * Who: anyone who can award ranks somewhere (owner, admin or coach of a
      box, a solo coach), checked against the person's memberships.
    * What: one PNG or JPEG of at most `max_bytes/0`, between
      `min_dimensions/0` and `max_dimensions/0` pixels. The stored bytes
      decide the type (magic bytes, never the client's word), and the image
      must be one the PDF writer can embed (`Palee.Pdf.Image`): a WebP is
      turned into a PNG by the browser before it is sent.
    * Where: `users/<user id>/diploma-signature/<id>.<ext>` in the private
      media bucket; never a public URL.
  """

  alias Palee.Pdf.Image

  @max_bytes 512 * 1024
  @min_dimensions {60, 20}
  @max_dimensions {1600, 800}
  @signing_roles ~w(owner admin coach)
  @types %{"image/png" => "png", "image/jpeg" => "jpg"}

  def max_bytes, do: @max_bytes
  def min_dimensions, do: @min_dimensions
  def max_dimensions, do: @max_dimensions
  def content_types, do: @types |> Map.keys() |> Enum.sort()
  def signing_roles, do: @signing_roles

  @doc "Whether any of the person's roles (strings or atoms) can award ranks."
  def can_sign?(roles) when is_list(roles),
    do: Enum.any?(roles, &(to_string(&1) in @signing_roles))

  @doc "The storage prefix every signature object of the person starts with."
  def prefix(user_id), do: "users/#{user_id}/diploma-signature/"

  def object_key(user_id, id, content_type),
    do: prefix(user_id) <> "#{id}.#{Map.fetch!(@types, content_type)}"

  def owned_key?(user_id, key) when is_binary(key),
    do: String.starts_with?(key, prefix(user_id)) and not String.contains?(key, "..")

  def owned_key?(_user_id, _key), do: false

  @doc """
  Checks uploaded bytes: `{:ok, %{content_type, width, height, byte_size,
  sha256}}` or `{:error, reason}`.
  """
  def validate(bytes) when is_binary(bytes) do
    with :ok <- check_size(byte_size(bytes)),
         {:ok, content_type} <- sniff(bytes),
         {:ok, image} <- embeddable(bytes),
         :ok <- check_dimensions(image) do
      {:ok,
       %{
         content_type: content_type,
         width: image.width,
         height: image.height,
         byte_size: byte_size(bytes),
         sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
       }}
    end
  end

  def validate(_bytes), do: {:error, :invalid_signature_image}

  defp check_size(0), do: {:error, :invalid_signature_image}
  defp check_size(size) when size > @max_bytes, do: {:error, :signature_too_large}
  defp check_size(_size), do: :ok

  defp sniff(<<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>>), do: {:ok, "image/png"}
  defp sniff(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "image/jpeg"}
  defp sniff(_bytes), do: {:error, :signature_unsupported_type}

  defp embeddable(bytes) do
    case Image.parse(bytes) do
      {:ok, image} -> {:ok, image}
      {:error, _reason} -> {:error, :signature_unsupported_type}
    end
  end

  defp check_dimensions(%{width: width, height: height}) do
    {min_w, min_h} = @min_dimensions
    {max_w, max_h} = @max_dimensions

    cond do
      width < min_w or height < min_h -> {:error, :signature_too_small}
      width > max_w or height > max_h -> {:error, :signature_dimensions_too_large}
      true -> :ok
    end
  end
end
