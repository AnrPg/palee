defmodule Palee.Infrastructure.Identity.EctoAccountDeletionStore do
  @moduledoc "Ecto adapter of `Palee.Identity.Ports.AccountDeletionStore` (ADR-211)."
  @behaviour Palee.Identity.Ports.AccountDeletionStore

  import Ecto.Query

  alias Palee.Identity.{AccountDeletion, Login, PasswordHasher, User}
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  # What an anonymised profile shows wherever a business record still names
  # it (an invoice list, a ledger). Not a translation key: the stored row is
  # the same in every language, and it says nothing about the person.
  @anonymous_name "Deleted account"

  @impl true
  def for_login(login_id),
    do: AccountDeletion |> where([d], d.login_id == ^login_id) |> Repo.one()

  @impl true
  def get(id), do: Repo.get(AccountDeletion, id)

  @impl true
  def open(attrs) do
    Repo.transaction(fn ->
      existing =
        AccountDeletion
        |> where([d], d.login_id == ^attrs.login_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case existing do
        %AccountDeletion{status: :scheduled} ->
          Repo.rollback(:already_scheduled)

        %AccountDeletion{} = awaiting ->
          Repo.delete!(awaiting)

        nil ->
          :ok
      end

      %AccountDeletion{}
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert!()
    end)
  end

  @impl true
  def schedule(id, now, scheduled_for) do
    Repo.transaction(fn ->
      case AccountDeletion |> where([d], d.id == ^id) |> lock("FOR UPDATE") |> Repo.one() do
        nil ->
          Repo.rollback(:not_found)

        %AccountDeletion{status: :scheduled} ->
          Repo.rollback(:already_scheduled)

        deletion ->
          deletion
          |> Ecto.Changeset.change(
            status: :scheduled,
            confirmed_at: now,
            scheduled_for: scheduled_for
          )
          |> Repo.update!()
      end
    end)
  end

  @impl true
  def delete(id) do
    AccountDeletion |> where([d], d.id == ^id) |> Repo.delete_all()
    :ok
  end

  @impl true
  def due(now, limit) do
    AccountDeletion
    |> where([d], d.status == :scheduled and d.scheduled_for <= ^now)
    |> order_by([d], asc: d.scheduled_for, asc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def sole_owned_organizations([]), do: []

  def sole_owned_organizations(user_ids) when is_list(user_ids) do
    ids = Enum.map(user_ids, &Ecto.UUID.dump!/1)

    Repo.query!(
      "SELECT organization_id, organization_name FROM palee_sole_owned_organizations($1) ORDER BY organization_name",
      [ids]
    ).rows
    |> Enum.map(fn [id, name] -> %{id: Ecto.UUID.load!(id), name: name} end)
  end

  @impl true
  def has_retained_records?(user_id) do
    %{rows: [[retained?]]} =
      Repo.query!("SELECT palee_user_has_retained_records($1)", [Ecto.UUID.dump!(user_id)])

    retained?
  end

  @impl true
  def deleting_profile_memberships(user_id) do
    Repo.query!(
      "SELECT organization_id, membership_id FROM palee_deleting_profile_memberships($1)",
      [Ecto.UUID.dump!(user_id)]
    ).rows
    |> Enum.map(fn [organization_id, membership_id] ->
      %{
        organization_id: Ecto.UUID.load!(organization_id),
        membership_id: Ecto.UUID.load!(membership_id)
      }
    end)
  end

  @impl true
  def anonymize_profile(user_id) do
    Repo.transaction(fn ->
      case User |> where([u], u.id == ^user_id) |> lock("FOR UPDATE") |> Repo.one() do
        nil -> Repo.rollback(:not_found)
        user -> anonymize(user)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_login_if_empty(login_id) do
    unless User |> where([u], u.login_id == ^login_id) |> Repo.exists?() do
      Login |> where([l], l.id == ^login_id) |> Repo.delete_all()
    end

    :ok
  end

  # ADR-280: Partners rows are the person's own and leave with the account
  # even when the profile itself is kept anonymised (a deleted user row
  # takes them by cascade).
  @partner_rows [
    {"partner_reports", ~w(reporter_id target_id)},
    {"partner_matches", ~w(user_a_id user_b_id)},
    {"partner_swipes", ~w(swiper_id target_id)},
    {"partner_profiles", ~w(user_id)}
  ]

  defp delete_partner_rows(user_id) do
    id = Ecto.UUID.dump!(user_id)

    for {table, columns} <- @partner_rows do
      condition = Enum.map_join(columns, " OR ", &"#{&1} = $1")
      Repo.query!("DELETE FROM #{table} WHERE #{condition}", [id])
    end

    :ok
  end

  # Rows only their owner may touch (forced owner RLS): the deletion worker
  # runs without a session scope, so these deletes run in the person's own
  # scope, or under the runtime role they would delete nothing.
  #   * ADR-395: a kept (anonymised) profile keeps no body weight or birth year;
  #   * ADR-394: it leaves every Palee-wide board;
  #   * ADR-375/376: a watch's heart rate, paired watches and own foods are the
  #     person's own and leave with the account even when the profile is kept
  #     anonymised (a deleted user row takes them by cascade).
  @owner_rows ~w(fitness_profile_settings palee_leaderboard_consents
                 execution_heart_rate_batches watch_offers watch_links custom_foods)

  defp delete_owner_rows(user_id) do
    id = Ecto.UUID.dump!(user_id)

    :ok =
      RepoContext.run(%{user_id: user_id}, fn ->
        Enum.each(@owner_rows, &Repo.query!("DELETE FROM #{&1} WHERE user_id = $1", [id]))
      end)
  end

  # ADR-395: what each box's coach chose the person's fitness card shows.
  # Those rows are in the boxes' scopes, which the sweep cannot enter, so a
  # definer function deletes them, and only for a profile whose deletion is
  # scheduled.
  defp delete_fitness_overrides(user_id) do
    Repo.query!("SELECT palee_forget_fitness_overrides($1)", [Ecto.UUID.dump!(user_id)])
    :ok
  end

  defp anonymize(%User{} = user) do
    # A login of its own: the person's login (and email) can go, and nobody
    # knows this one's address or password.
    tombstone =
      Repo.insert!(%Login{
        email: "deleted+#{user.id}@deleted.invalid",
        password_hash: PasswordHasher.hash(Base.encode64(:crypto.strong_rand_bytes(32))),
        security_version: 0
      })

    Login
    |> where([l], l.id == ^user.login_id and l.last_used_user_id == ^user.id)
    |> Repo.update_all(set: [last_used_user_id: nil])

    "handle_reservations"
    |> where([r], r.user_id == ^Ecto.UUID.dump!(user.id))
    |> Repo.delete_all()

    delete_partner_rows(user.id)

    # ADR-397: the person's reports on box reviews (a tenant table, so
    # through its SECURITY DEFINER function).
    Repo.query!("SELECT palee_forget_box_review_reports($1)", [Ecto.UUID.dump!(user.id)])

    # ADR-421 addendum: a product the person shared stays shared (it holds
    # nothing about them), but who shared it goes.
    Repo.query!("UPDATE food_product_shares SET user_id = NULL WHERE user_id = $1", [
      Ecto.UUID.dump!(user.id)
    ])

    delete_owner_rows(user.id)
    delete_fitness_overrides(user.id)

    user
    |> Ecto.Changeset.change(
      handle: "deleted." <> Base.encode16(:crypto.strong_rand_bytes(5), case: :lower),
      display_name: @anonymous_name,
      search_text: "",
      handle_changed_at: nil,
      avatar_url: nil,
      time_zone: nil,
      trains_with_palee: nil,
      preferred_theme_slug: nil,
      completed_tours: [],
      login_id: tombstone.id,
      security_version: (user.security_version || 1) + 1,
      calendar_feed_token_version: (user.calendar_feed_token_version || 1) + 1
    )
    |> Repo.update!()

    :ok
  end
end
