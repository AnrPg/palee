defmodule Palee.Application.UpdateFinancePackage do
  alias Palee.Application.Fiscal.SoldItemTax
  alias Palee.Application.PackageBranches
  alias Palee.Application.Payments.OnlineSales
  alias Palee.{Finance, Identity, Notifications}

  def call(id, params), do: Finance.update_package(id, params)

  @doc """
  ADR-186 §8: only a package valid inside the acting branches changes.
  ADR-271: a `sold_online` sent by staff is the owner's choice.
  ADR-770: `terms_choice` (`apply_to`: `"active"` or `"new_only"`,
  `excluded_subscription_ids`) says whether the change reaches the members
  who hold the package; it is required when it would reach them. The
  members it reaches hear what changes and from when.
  """
  def call(context, id, params, now \\ DateTime.utc_now()) do
    {choice, params} = split_choice(params)

    with :ok <- SoldItemTax.check(context, params),
         :ok <- PackageBranches.authorize_change(context, id, params),
         {:ok, %{package: package, notices: notices}} <-
           Finance.update_package_with_terms(
             context,
             id,
             OnlineSales.owner_choice(params, now),
             choice,
             Map.get(context, :user_id)
           ) do
      notify_members(context, package, notices)
      {:ok, OnlineSales.with_visibility(context, package)}
    end
  end

  @doc """
  ADR-770: what saving `params` would do to the package's holders, with
  each holder's name, for «Ισχύει και για τα ενεργά μέλη;». Nothing is saved.
  """
  def preview(context, id, params, now \\ DateTime.utc_now()) do
    {_choice, params} = split_choice(params)

    with :ok <- SoldItemTax.check(context, params),
         :ok <- PackageBranches.authorize_change(context, id, params),
         {:ok, preview} <-
           Finance.preview_package_terms(context, id, OnlineSales.owner_choice(params, now)) do
      names =
        preview.holders
        |> Enum.map(& &1.user_id)
        |> Identity.list_by_ids()
        |> Map.new(&{&1.id, &1.nickname})

      holders =
        preview.holders
        |> Enum.map(&Map.put(&1, :nickname, Map.get(names, &1.user_id)))
        |> Enum.sort_by(&String.downcase(&1.nickname || ""))

      {:ok, %{preview | holders: holders}}
    end
  end

  defp split_choice(params) when is_map(params) do
    raw = Map.get(params, "terms_choice") || Map.get(params, :terms_choice) || %{}

    choice = %{
      apply_to: value(raw, "apply_to"),
      excluded_subscription_ids:
        raw |> value("excluded_subscription_ids") |> List.wrap() |> Enum.filter(&is_binary/1)
    }

    {choice, params |> Map.delete("terms_choice") |> Map.delete(:terms_choice)}
  end

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, String.to_atom(key)))
  defp value(_other, _key), do: nil

  defp notify_members(_context, _package, []), do: :ok

  defp notify_members(context, package, notices) do
    box =
      context.organization_id
      |> List.wrap()
      |> Palee.Application.PublicBox.boxes()
      |> List.first() || %{}

    Enum.each(notices, fn notice ->
      Notifications.process_event("package_terms_changed", %{
        organization_id: context.organization_id,
        user_id: notice.user_id,
        subscription_id: notice.subscription_id,
        term_change_id: notice.term_change_id,
        box_name: Map.get(box, :name),
        box_slug: Map.get(box, :slug),
        package_name: package[:name],
        now_count: notice.now_count,
        next_on: notice.next_on
      })
    end)
  end
end
