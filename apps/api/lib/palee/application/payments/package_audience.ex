defmodule Palee.Application.Payments.PackageAudience do
  @moduledoc """
  ADR-553: who sees a box's subscription packages, on its Palee page and its
  website alike. The rules live in `Finance.Domain.PackageAudience`; this
  module reads what the box chose and who is looking, and is the one gate
  for every list and every way to get a package:

    * the package lists (`view/2`) the public page, the website and the
      member's renewal read;
    * buying, asking for it at the desk and joining by a package
      (`visible?/3`): what someone does not see they cannot get, not even by
      a link. The front desk can always give any package.

  Staff settings (`settings/1`, `set_box/2`, `set_package/3`,
  `put_exception/2`, `delete_exception/2`, `set_featured/2`) answer with the
  settings again.

  ADR-596: the box may feature one package («Προτεινόμενο»); the lists mark
  it with `featured`, only when the viewer sees it.
  """

  alias Palee.Application.Payments.OnlineSales
  alias Palee.{Finance, Identity}
  alias Palee.Finance.Domain.PackageAudience

  @doc """
  What `user_id` (nil: not signed in) sees of the packages the box lists:
  `%{packages, own_only}`. `own_only` asks the page for «Το πακέτο
  συνδρομής σου είναι X…».
  """
  def view(context, user_id) do
    listed = OnlineSales.listed_packages(context)
    %{policy: policy, featured: featured} = Finance.package_audience(context)

    listed
    |> PackageAudience.view(policy, Finance.package_viewer(context, user_id))
    |> Map.put(:featured, featured)
  end

  @doc "Whether `user_id` sees `package_id` (it must also be listed for sale elsewhere)."
  def visible?(context, package_id, user_id) do
    %{policy: policy} = Finance.package_audience(context)
    PackageAudience.shown?(package_id, policy, Finance.package_viewer(context, user_id))
  end

  @doc "`:ok` or `{:error, :package_not_for_sale}`, like a package that is not sold."
  def check(context, package_id, user_id) do
    if visible?(context, package_id, user_id), do: :ok, else: {:error, :package_not_for_sale}
  end

  # ── Staff ──────────────────────────────────────────────────────────────

  @doc "`%{audience, featured_package_id, exceptions: [%{id, package_id, effect, person}]}`."
  def settings(context) do
    %{policy: policy, exceptions: exceptions, featured: featured} =
      Finance.package_audience(context)

    people =
      exceptions
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1})

    {:ok,
     %{
       audience: policy.box,
       featured_package_id: featured,
       exceptions:
         for exception <- exceptions do
           %{
             id: exception.id,
             package_id: exception.package_id,
             effect: exception.effect,
             person: present_person(Map.get(people, exception.user_id), exception.user_id)
           }
         end
     }}
  end

  defp present_person(nil, id), do: %{id: id, nickname: nil, handle: nil, avatar_url: nil}

  defp present_person(person, _id) do
    %{
      id: person.id,
      nickname: person.nickname,
      handle: Map.get(person, :handle),
      avatar_url: Map.get(person, :avatar_url)
    }
  end

  def set_box(context, audience) do
    with {:ok, _audience} <- Finance.set_box_package_audience(context, audience),
         do: settings(context)
  end

  @doc "ADR-596: features `package_id` on the public page and website (nil: none)."
  def set_featured(context, package_id) do
    with {:ok, id} <- cast_optional_id(package_id),
         {:ok, _featured} <- Finance.set_featured_package(context, id),
         do: settings(context)
  end

  @doc "A package's own audience; nil follows the box. Answers `%{id, audience}`."
  def set_package(context, package_id, audience) do
    with {:ok, id} <- cast_id(package_id),
         do: Finance.set_package_audience(context, id, audience)
  end

  @doc "`params`: `user_id`, `effect` (show, hide), `package_id` (nil: every package)."
  def put_exception(context, params) do
    with {:ok, user_id} <- cast_id(params["user_id"] || params[:user_id]),
         {:ok, package_id} <- cast_optional_id(params["package_id"] || params[:package_id]),
         true <- Identity.list_by_ids([user_id]) != [] || {:error, :not_found},
         {:ok, _exception} <-
           Finance.put_package_audience_exception(context, %{
             user_id: user_id,
             package_id: package_id,
             effect: params["effect"] || params[:effect],
             created_by_id: Map.get(context, :user_id)
           }) do
      settings(context)
    end
  end

  def delete_exception(context, id) do
    with {:ok, id} <- cast_id(id),
         :ok <- Finance.delete_package_audience_exception(context, id),
         do: settings(context)
  end

  defp cast_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp cast_optional_id(value) when value in [nil, ""], do: {:ok, nil}
  defp cast_optional_id(value), do: cast_id(value)
end
