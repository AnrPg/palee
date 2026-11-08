defmodule Palee.Finance.Domain.PackageAudience do
  @moduledoc """
  ADR-553: who sees a box's subscription packages, on its page in Palee and
  on its website alike. Pure rules; the one place every reader asks (the
  package lists, buying, asking at the desk, joining by a package).

  A package already listed for sale (`Payments.Domain.PackageSale.listed?/2`)
  is shown to a viewer by the first step below that has an opinion; the more
  specific always wins over the more general:

    1. a person exception on the package (`hide` wins over `show`);
    2. a person exception on the whole box (`hide` wins over `show`);
    3. the package's own audience, unless it follows the box (`nil`);
    4. the box's audience.

  Audiences: `all` (everyone, also people who are not signed in), `own`
  (only the people who hold the package) and `none` (no one). Person
  exceptions apply only to a signed-in viewer: without one nobody is known.

  A viewer holds a package (`holdings/2`) when they have a running
  subscription of it, or it is the package of their latest subscription
  while they are still a box member, so they can renew it.
  """

  @audiences ~w(all own none)
  @effects ~w(show hide)
  @running ~w(active paused)

  defstruct box: "all", packages: %{}, exceptions: []

  @type audience :: String.t()
  @type exception :: %{
          required(:user_id) => Ecto.UUID.t(),
          required(:effect) => String.t(),
          optional(:package_id) => Ecto.UUID.t() | nil
        }
  @type t :: %__MODULE__{
          box: audience(),
          packages: %{optional(Ecto.UUID.t()) => audience() | nil},
          exceptions: [exception()]
        }
  @type viewer :: %{user_id: Ecto.UUID.t() | nil, holds: MapSet.t()}
  @type reason ::
          {:person, :package | :box, :show | :hide} | {:package | :box, audience()}

  @doc "The audiences a box or a package may have (a package may also have `nil`)."
  def audiences, do: @audiences

  @doc "What a person exception does."
  def effects, do: @effects

  @doc "A viewer nobody knows: not signed in."
  def anonymous, do: %{user_id: nil, holds: MapSet.new()}

  @doc "A signed-in viewer and the package ids they hold."
  def viewer(user_id, holds), do: %{user_id: user_id, holds: MapSet.new(holds)}

  @doc """
  Builds the policy from what is stored: the box's audience (`nil` reads as
  `all`), `%{package_id => audience | nil}` and the person exceptions.
  """
  def policy(box_audience, package_audiences, exceptions) do
    %__MODULE__{
      box: if(box_audience in @audiences, do: box_audience, else: "all"),
      packages: Map.new(package_audiences, fn {id, value} -> {id, known(value)} end),
      exceptions: Enum.filter(exceptions, &(&1[:effect] in @effects and is_binary(&1[:user_id])))
    }
  end

  defp known(value) when value in @audiences, do: value
  defp known(_value), do: nil

  @doc "Whether `value` is a valid audience; `allow_nil?` for a package (follows the box)."
  def valid?(value, allow_nil? \\ false)
  def valid?(nil, allow_nil?), do: allow_nil?
  def valid?(value, _allow_nil?), do: value in @audiences

  @doc """
  `{shown?, reason}` for one package: the step that decided (see the
  moduledoc), so a test or a staff hint can name it.
  """
  @spec decide(Ecto.UUID.t(), t(), viewer()) :: {boolean(), reason()}
  def decide(package_id, %__MODULE__{} = policy, viewer) do
    with :none <- person(policy, viewer, package_id, :package),
         :none <- person(policy, viewer, nil, :box) do
      case Map.get(policy.packages, package_id) do
        nil -> by_audience(policy.box, :box, package_id, viewer)
        audience -> by_audience(audience, :package, package_id, viewer)
      end
    end
  end

  @doc "Whether the viewer sees the package."
  def shown?(package_id, policy, viewer), do: package_id |> decide(policy, viewer) |> elem(0)

  defp person(_policy, %{user_id: nil}, _package_id, _level), do: :none

  defp person(policy, %{user_id: user_id}, package_id, level) do
    effects =
      for exception <- policy.exceptions,
          exception.user_id == user_id,
          Map.get(exception, :package_id) == package_id,
          do: exception.effect

    cond do
      "hide" in effects -> {false, {:person, level, :hide}}
      "show" in effects -> {true, {:person, level, :show}}
      true -> :none
    end
  end

  defp by_audience("all", level, _package_id, _viewer), do: {true, {level, "all"}}
  defp by_audience("none", level, _package_id, _viewer), do: {false, {level, "none"}}

  defp by_audience("own", level, package_id, viewer),
    do: {MapSet.member?(viewer.holds, package_id), {level, "own"}}

  @doc """
  What the viewer sees of `packages` (each with an `id`), in their order:
  `packages` shown, `held` (the ids of those the viewer holds), and
  `own_only` when the viewer sees packages they hold
  while others are kept for their holders. Then the page says «Το πακέτο
  συνδρομής σου είναι X. Επικοινώνησε με το box για να δεις κι άλλα.»
  """
  def view(packages, %__MODULE__{} = policy, viewer) do
    decided = Enum.map(packages, &{&1, decide(&1.id, policy, viewer)})
    shown = for {package, {true, _reason}} <- decided, do: package

    kept_for_holders? =
      Enum.any?(decided, fn {_package, {shown?, reason}} ->
        not shown? and match?({_level, "own"}, reason)
      end)

    held = for package <- shown, MapSet.member?(viewer.holds, package.id), do: package.id

    %{packages: shown, held: held, own_only: kept_for_holders? and held != []}
  end

  @doc """
  The package ids a viewer holds, from their subscriptions at the box
  (`membership_package_id`, `status`, `inserted_at`) and whether they are
  still a box member: every running one, plus the latest one while they
  are a member (to renew it). Two packages: both.
  """
  def holdings(subscriptions, member?) do
    running = for sub <- subscriptions, sub.status in @running, do: sub.membership_package_id

    latest =
      if member? and subscriptions != [] do
        subscriptions
        |> Enum.max_by(&sort_key/1, fn -> nil end)
        |> Map.get(:membership_package_id)
        |> List.wrap()
      else
        []
      end

    (running ++ latest) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp sort_key(sub) do
    {date_key(Map.get(sub, :starts_on)), datetime_key(Map.get(sub, :inserted_at))}
  end

  defp date_key(%Date{} = date), do: Date.to_gregorian_days(date)
  defp date_key(_none), do: 0

  defp datetime_key(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)

  defp datetime_key(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> datetime_key()

  defp datetime_key(_none), do: 0
end
