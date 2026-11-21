defmodule Palee.Payments.Domain.PackageSale do
  @moduledoc """
  Whether members can see and buy a package online (ADR-248/260/271). The
  one place of the rules: the public package page, the staff package list
  (`online_visibility`) and the automatic «Πωλείται online» all ask here.

  `offer` describes the business's online payments:
  `%{available: boolean, options: map}` (`options`: the account's
  «Τι πληρώνεται online», `AccountOptions`).

  `visibility/2` answers, in order:

    * `inactive` – the package is retired;
    * `free` – a price of 0 the owner keeps off the package page;
    * `free_listed` – ADR-681: a price of 0 listed on the package page
      (also on the box website) with «Δωρεάν», to ask for («Το θέλω») and
      have the box activate without any payment, with or without online
      payments; listed until the owner turns it off, like a paid package
      at a box without online payments (ANR 2026-11-21);
    * `off` – the box sells it only at the front desk;
    * `purpose_off` – the provider is connected but «Τι πληρώνεται online»
      leaves its purpose off;
    * `no_provider` – no online payments: listed on the package page to ask
      for («Το θέλω») and pay at the front desk (ADR-291); a package whose
      owner never chose is listed too, and opens online on connecting;
    * `visible` – listed and bought online.
  """

  alias Palee.Finance.Domain.PackageRequestPolicy
  alias Palee.Payments.Domain.AccountOptions

  @visibilities ~w(visible free free_listed off purpose_off no_provider inactive)

  def visibilities, do: @visibilities

  @doc "ADR-260: which «Τι πληρώνεται online» switch covers a package."
  def purpose(%{package_type: "pt_pack"}), do: "personal_training"
  def purpose(%{package_type: type}) when type in ["drop_in", "trial"], do: "drop_in"
  def purpose(_package), do: "packages"

  def visibility(package, offer) do
    cond do
      package[:active] != true -> "inactive"
      not paid?(package) -> if(desk_listed?(package), do: "free_listed", else: "free")
      not offer.available and desk_listed?(package) -> "no_provider"
      package[:sold_online] != true -> "off"
      not offer.available -> "no_provider"
      not allowed?(package, offer) -> "purpose_off"
      true -> "visible"
    end
  end

  # ADR-291: without online payments the package page lists every paid
  # package its owner never kept off, to ask for and pay at the front desk;
  # connecting later turns those same packages on (ADR-271 `opens?/2`).
  # ADR-681: a free package is listed the same way, whatever the payments.
  defp desk_listed?(package) do
    package[:sold_online] == true or
      (package[:sold_online_chosen_at] == nil and
         package[:package_type] not in PackageRequestPolicy.needs_more())
  end

  @doc "Whether the public package page lists it (bought or not yet)."
  def listed?(package, offer),
    do: visibility(package, offer) in ["visible", "no_provider", "free_listed"]

  @doc """
  How a listed package is taken: `buy` online, or `ask` («Το θέλω»): paid at
  the front desk (ADR-291) or, when free, activated by the box (ADR-681).
  Nil when it is not listed.
  """
  def how(package, offer) do
    case visibility(package, offer) do
      "visible" -> "buy"
      visibility when visibility in ["no_provider", "free_listed"] -> "ask"
      _hidden -> nil
    end
  end

  @doc "ADR-681: a package with a price of 0 (never paid for, online or at the desk)."
  def free?(package), do: is_integer(package[:base_price_cents]) and package.base_price_cents == 0

  @doc """
  ADR-271: whether connecting online payments switches the package on: active,
  paid, its purpose allowed, and its owner never chose for it.
  """
  def opens?(package, offer) do
    package[:active] == true and paid?(package) and package[:sold_online_chosen_at] == nil and
      allowed?(package, offer)
  end

  @doc "ADR-271: a package created while online payments work starts sold online."
  def default_on?(package, offer), do: offer.available and opens?(package, offer)

  defp paid?(package), do: is_integer(package[:base_price_cents]) and package.base_price_cents > 0

  defp allowed?(package, offer),
    do: AccountOptions.allows?(offer[:options] || %{}, purpose(package))
end
