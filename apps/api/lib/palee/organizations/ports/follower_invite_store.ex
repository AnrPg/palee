defmodule Palee.Organizations.Ports.FollowerInviteStore do
  @moduledoc """
  ADR-580: where a box's invitations to its followers are kept, and who
  follows the box. Every call runs inside the caller's scope
  (`FollowerInviteStore.with_scope/2`): the box's (`organization_id`) for
  its list and its invitations, the box's and the person's together for the
  person's own. Rows come back as plain maps.
  """

  @type invite :: map()
  @type follower :: %{
          user_id: Ecto.UUID.t(),
          followed_at: DateTime.t(),
          former_member: boolean(),
          had_trial: boolean(),
          invite_status: String.t() | nil,
          invited_at: DateTime.t() | nil,
          invitable: boolean()
        }

  @doc """
  The box's followers who may be listed, newest follow first, `limit` at a
  time after the `before` cursor (`{followed_at, user_id}` or nil); `now`
  decides who may be invited again.
  """
  @callback list_followers(
              String.t(),
              pos_integer(),
              {DateTime.t(), Ecto.UUID.t()} | nil,
              DateTime.t()
            ) :: [follower()]

  @doc "How many are listed, may be invited now, did a trial, were box members."
  @callback counts(DateTime.t()) :: %{
              listed: non_neg_integer(),
              invitable: non_neg_integer(),
              trial: non_neg_integer(),
              former: non_neg_integer()
            }

  @doc "Of `user_ids`, the listed followers, keyed by id (to check a send)."
  @callback followers_among([Ecto.UUID.t()], DateTime.t()) :: %{Ecto.UUID.t() => follower()}

  @doc "Records one invitation per person (same content), all or none."
  @callback create_many([Ecto.UUID.t()], map(), DateTime.t()) ::
              {:ok, [invite()]} | {:error, term()}

  @doc "The person's latest invitation from the box in scope (a declined one first), or nil."
  @callback latest_for(Ecto.UUID.t()) :: invite() | nil

  @doc "Declines every open invitation of the person from the box in scope."
  @callback decline(Ecto.UUID.t(), DateTime.t()) :: {:ok, invite() | nil} | {:error, term()}
end
