defmodule PaleeWeb.Schemas.FollowerInvites do
  @moduledoc "ADR-580: a box's invitations to its followers to become box members."

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time"}

  defp package do
    %Schema{
      title: "FollowerInvitePackage",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        price_cents: %Schema{type: :integer},
        currency: %Schema{type: :string},
        billing_period: %Schema{type: :string, nullable: true}
      },
      required: [:billing_period, :currency, :id, :name, :price_cents]
    }
  end

  def counts do
    %Schema{
      title: "FollowerInviteCounts",
      type: :object,
      description:
        "Followers who are not box members: listed, may be invited now, did a trial, former box members",
      properties: %{
        listed: %Schema{type: :integer, minimum: 0},
        invitable: %Schema{type: :integer, minimum: 0},
        trial: %Schema{type: :integer, minimum: 0},
        former: %Schema{type: :integer, minimum: 0}
      },
      required: [:former, :invitable, :listed, :trial]
    }
  end

  def summary_response do
    %Schema{
      title: "FollowerInviteSummaryResponse",
      type: :object,
      properties: %{counts: counts()},
      required: [:counts]
    }
  end

  def list_response do
    follower = %Schema{
      title: "BoxFollower",
      type: :object,
      properties: %{
        person: %Schema{
          title: "BoxFollowerPerson",
          type: :object,
          properties: %{
            id: @uuid,
            nickname: %Schema{type: :string},
            handle: %Schema{type: :string, nullable: true},
            avatar_url: %Schema{type: :string, nullable: true}
          },
          required: [:avatar_url, :handle, :id, :nickname]
        },
        followed_at: @time,
        former_member: %Schema{type: :boolean},
        had_trial: %Schema{type: :boolean},
        invite: %Schema{
          title: "BoxFollowerInvite",
          type: :object,
          nullable: true,
          description:
            "The latest invitation: sent (next_invite_at: when the box may invite again) or declined (never again)",
          properties: %{
            status: %Schema{type: :string, enum: ~w(sent declined)},
            sent_at: @time,
            next_invite_at: %Schema{type: :string, format: :"date-time", nullable: true}
          },
          required: [:next_invite_at, :sent_at, :status]
        },
        invitable: %Schema{type: :boolean}
      },
      required: [:followed_at, :former_member, :had_trial, :invitable, :invite, :person]
    }

    %Schema{
      title: "BoxFollowerList",
      type: :object,
      properties: %{
        followers: %Schema{type: :array, items: follower},
        next_cursor: %Schema{type: :string, nullable: true},
        counts: counts(),
        offer: %Schema{
          title: "FollowerInviteOffer",
          type: :object,
          description:
            "What a send may hold: packages listed to everyone, and whether trials are open",
          properties: %{
            packages: %Schema{type: :array, items: package()},
            trial_available: %Schema{type: :boolean}
          },
          required: [:packages, :trial_available]
        }
      },
      required: [:counts, :followers, :next_cursor, :offer]
    }
  end

  def send_request do
    %Schema{
      title: "FollowerInviteSendRequest",
      type: :object,
      properties: %{
        user_ids: %Schema{type: :array, items: @uuid, minItems: 1, maxItems: 200},
        message: %Schema{type: :string, maxLength: 500, nullable: true},
        package_id: %Schema{type: :string, format: :uuid, nullable: true},
        offer_trial: %Schema{type: :boolean}
      },
      required: [:user_ids]
    }
  end

  def send_response do
    %Schema{
      title: "FollowerInviteSendResponse",
      type: :object,
      properties: %{
        sent: %Schema{type: :integer, minimum: 0},
        skipped: %Schema{
          type: :array,
          items: %Schema{
            title: "FollowerInviteSkipped",
            type: :object,
            properties: %{
              user_id: @uuid,
              reason: %Schema{type: :string, enum: ~w(declined recently_invited not_a_follower)}
            },
            required: [:reason, :user_id]
          }
        }
      },
      required: [:sent, :skipped]
    }
  end

  def mine_response do
    invite = %Schema{
      title: "MyFollowerInvite",
      type: :object,
      nullable: true,
      properties: %{
        id: @uuid,
        status: %Schema{type: :string, enum: ~w(sent declined)},
        sent_at: @time,
        message: %Schema{type: :string, nullable: true},
        offer_trial: %Schema{type: :boolean},
        package: %Schema{allOf: [package()], nullable: true},
        box: %Schema{
          type: :object,
          properties: %{slug: %Schema{type: :string}, name: %Schema{type: :string}},
          required: [:name, :slug]
        }
      },
      required: [:box, :id, :message, :offer_trial, :package, :sent_at, :status]
    }

    %Schema{
      title: "MyFollowerInviteResponse",
      type: :object,
      properties: %{invite: invite},
      required: [:invite]
    }
  end
end
