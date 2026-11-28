defmodule PaleeWeb.AdminUserController do
  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.{
    GetAdminUserCoachingContext,
    GetAdminUserFinance,
    GetAdminUserIncidents,
    GetAdminUserMessages,
    GetAdminUserProfile,
    GetAdminUserPRs,
    GetAdminUserSchedule,
    GetAdminUserTrainingHistory,
    GetClassPlacementOptions,
    DeleteAdminUser,
    ListAdminUsers,
    ListAthletes,
    ListPRDossierMembers,
    PlaceMemberInClass,
    PlaceMemberOnWaitlist,
    ProgramUserWorkout,
    ProgramWorkoutForUsers
  }

  alias Palee.Finance
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Users"])
  security([%{"bearerAuth" => []}])

  @id_parameter %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @user_id %Schema{type: :string, format: :uuid}
  @summary_object %Schema{type: :object, additionalProperties: true}
  @finance_details %Schema{
    type: :object,
    required: [
      :membership,
      :package_subscriptions,
      :referral_claims,
      :referred_members,
      :referral_rewards
    ],
    properties: %{
      membership: %Schema{type: :object, additionalProperties: true, nullable: true},
      package_subscriptions: %Schema{type: :array, items: @summary_object},
      referral_claims: %Schema{type: :array, items: @summary_object},
      referred_members: %Schema{type: :array, items: @summary_object},
      referral_rewards: %Schema{type: :array, items: @summary_object}
    }
  }
  @finance_response %Schema{
    type: :object,
    required: [:user_id, :available, :summary, :details, :drill_down, :operational_links],
    properties: %{
      user_id: @user_id,
      available: %Schema{type: :boolean},
      summary: %Schema{
        type: :object,
        additionalProperties: true,
        nullable: true,
        properties: %{standing: PaleeWeb.Schemas.MemberStanding.schema()}
      },
      details: @finance_details,
      drill_down: %Schema{type: :object, additionalProperties: true, nullable: true},
      operational_links: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
    }
  }
  @training_response %Schema{
    type: :object,
    required: [:user_id, :executions, :scores, :class_participation, :assigned_workouts, :summary],
    properties: %{
      user_id: @user_id,
      executions: %Schema{type: :array, items: @summary_object},
      scores: %Schema{type: :array, items: @summary_object},
      class_participation: %Schema{type: :array, items: @summary_object},
      assigned_workouts: %Schema{type: :array, items: @summary_object},
      summary: @summary_object
    }
  }
  @collection_response %Schema{
    type: :object,
    required: [:user_id],
    properties: %{
      user_id: @user_id,
      prs: %Schema{type: :array, items: @summary_object},
      incidents: %Schema{type: :array, items: @summary_object},
      threads: %Schema{type: :array, items: @summary_object},
      summary: @summary_object,
      operational_links: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
    }
  }
  @pr_response %Schema{
    type: :object,
    required: [:user_id, :visibility, :prs],
    properties: %{
      user_id: @user_id,
      visibility: %Schema{
        type: :string,
        enum: ["coach", "coach_role_required"],
        description:
          "ADR-129: `coach` - PRs recorded in this gym that the member shares with its coaches; `coach_role_required` - the caller is staff but not a coach of this gym, so no PRs are returned."
      },
      member: %Schema{
        type: :object,
        nullable: true,
        description:
          "ADR-132: the PR owner's public identity when they are an active member of this gym, so a coach outside their client scope can still title the PR dossier.",
        required: [:id, :nickname],
        properties: %{
          id: @user_id,
          nickname: %Schema{type: :string},
          avatar_url: %Schema{type: :string, nullable: true}
        }
      },
      prs: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          additionalProperties: true,
          required: [:id, :name, :current_score, :unit, :higher_is_better, :beaten_on, :history],
          properties: %{
            id: @user_id,
            name: %Schema{type: :string},
            current_score: %Schema{type: :number},
            unit: %Schema{type: :string},
            higher_is_better: %Schema{type: :boolean},
            beaten_on: %Schema{type: :string, format: :date},
            history: %Schema{type: :array, items: @summary_object}
          }
        }
      }
    }
  }
  @pr_members_response %Schema{
    type: :object,
    required: [:visibility, :members],
    properties: %{
      visibility: %Schema{
        type: :string,
        enum: ["coach", "coach_role_required"],
        description:
          "ADR-132: `coach` - the gym's active members, whose PR panels the caller may open; `coach_role_required` - the caller is staff but not a coach, so no members are listed."
      },
      members: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          required: [:id, :nickname, :role],
          properties: %{
            id: @user_id,
            nickname: %Schema{type: :string},
            avatar_url: %Schema{type: :string, nullable: true},
            role: %Schema{type: :string},
            joined_at: %Schema{type: :string, format: :"date-time", nullable: true}
          }
        }
      }
    }
  }
  @coaching_response %Schema{
    type: :object,
    required: [:user_id, :available, :drill_down],
    properties: %{
      user_id: @user_id,
      available: %Schema{type: :boolean},
      drill_down: %Schema{type: :object, additionalProperties: true, nullable: true}
    }
  }

  @schedule_response %Schema{type: :object, additionalProperties: true}
  @program_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          properties: %{
            master_workout_id: @user_id,
            folder_id: %Schema{allOf: [@user_id], nullable: true},
            scheduled_for: %Schema{type: :string, format: :date},
            slot_id: %Schema{allOf: [@user_id], nullable: true},
            copy_source: %Schema{type: :boolean, default: true},
            offer_booking: %Schema{
              type: :boolean,
              description:
                "ADR-746: `class_variant` for a member who has not booked the class. It does not " <>
                  "book them: the WOD is in their programme that day and their notice opens the class."
            },
            instructions: %Schema{type: :string, nullable: true},
            mode: %Schema{
              type: :string,
              enum: ["class_workout", "class_variant", "personal"],
              description:
                "Member programming mode (ADR-125; ignored for athletes). " <>
                  "`class_variant` (default, ADR-785) assigns this member's own «Παραλλαγή» of one " <>
                  "class (source defaults to the WOD the member does in it when `master_workout_id` " <>
                  "is omitted), with no programming grant, until the class ends; " <>
                  "`class_workout` replaces the booked class's workout for everyone; " <>
                  "`personal` assigns a personal workout without a class and requires the " <>
                  "member's package to include personal programming."
            }
          },
          required: [:scheduled_for, :copy_source]
        }
      }
    }
  }

  # ADR-201: the same programming for several people, each treated as the only one.
  @program_many_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          properties:
            Map.put(
              @program_body.content["application/json"].schema.properties,
              :user_ids,
              %Schema{
                type: :array,
                items: @user_id,
                minItems: 1,
                maxItems: 50,
                description: "The people to program; duplicates are ignored (at most 50)."
              }
            ),
          required: [:user_ids, :scheduled_for, :copy_source]
        }
      }
    }
  }
  @program_many_result %Schema{
    type: :object,
    required: [:user_id, :status],
    properties: %{
      user_id: @user_id,
      status: %Schema{type: :string, enum: ["ok", "error"]},
      mode: %Schema{type: :string, description: "Set when `status` is ok."},
      workout: %Schema{type: :object, additionalProperties: true},
      association: %Schema{type: :object, additionalProperties: true},
      code: %Schema{
        type: :string,
        description: "Set when `status` is error: the code the one-person endpoint answers."
      },
      params: %Schema{type: :object, additionalProperties: true}
    }
  }
  @program_many_response %Schema{
    type: :object,
    required: [:results],
    properties: %{results: %Schema{type: :array, items: @program_many_result}}
  }

  @class_placement_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          properties: %{
            slot_id: @user_id,
            from_booking_id: %Schema{allOf: [@user_id], nullable: true}
          },
          required: [:slot_id]
        }
      }
    }
  }

  # ADR-790: staff put a member on a full class's waitlist.
  @class_waitlist_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          properties: %{
            slot_id: @user_id,
            position: %Schema{
              type: :string,
              enum: ["end", "first"],
              description: "«Στο τέλος» (default; package priority counts) or «Πρώτος στη σειρά»."
            }
          },
          required: [:slot_id]
        }
      }
    }
  }

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [
              :update_role,
              :program_workout,
              :program_workout_for_users,
              :change_client_roles,
              :preview_client_roles,
              :place_in_class,
              :place_on_waitlist,
              :freezes,
              :create_freeze,
              :cancel_freeze
            ]

  @membership_roles_response %Schema{
    type: :object,
    properties: %{
      membership: %Schema{
        type: :object,
        properties: %{
          user_id: %Schema{type: :string, format: :uuid},
          role: %Schema{type: :string},
          roles: %Schema{type: :array, items: %Schema{type: :string}},
          coach_scope: %Schema{type: :string, enum: ["own", "all"]},
          status: %Schema{type: :string},
          home_location_id: %Schema{type: :string, format: :uuid, nullable: true}
        },
        required: [:user_id, :role, :roles, :coach_scope]
      }
    },
    required: [:membership]
  }

  # Placing a member in a class or on its waitlist is authorized by the
  # application (ClassPlacementAccess, ADR-790): a coach may in the classes
  # they run, whoever the member is.
  # A coach with scope `:own` reaches only their own clients (ADR-100). PRs are
  # the exception: every coach of the gym reads members' PRs and coach scope
  # must not narrow that (ADR-129); the database policy enforces it instead.
  @client_actions %{
    show: [:view_directory, :view_billing_contacts],
    training_history: [:view_client_training],
    schedule: [:view_client_training, :run_classes],
    program_workout: [:manage_coaching],
    incidents: [:view_health],
    messages: [:message_clients],
    coaching_context: [:view_client_training]
  }

  plug :authorize_client
       when action in [
              :show,
              :training_history,
              :schedule,
              :program_workout,
              :incidents,
              :messages,
              :coaching_context
            ]

  defp authorize_client(conn, _opts) do
    capabilities = Map.fetch!(@client_actions, action_name(conn))
    client_id = conn.path_params["id"]

    allowed? =
      Enum.any?(capabilities, fn capability ->
        Palee.Application.AuthorizeClientAccess.call(
          conn.assigns.tenant_context,
          capability,
          client_id
        ) == :ok
      end)

    if allowed? do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{code: "not_your_client", error: "Not one of your clients"})
      |> halt()
    end
  end

  operation(:index,
    summary: "List all users for the admin directory",
    parameters: [
      %Parameter{name: :q, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :role,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["member", "athlete", "admin"]}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50}
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      }
    ],
    responses: [
      ok:
        {"User directory", "application/json", %Schema{type: :object, additionalProperties: true}}
    ]
  )

  operation(:show,
    summary: "Get the common role-aware admin user profile shell",
    description:
      "`programming` (clients only, else null): `{allowed, grant, reason}` says whether a WOD " <>
        "can be assigned to the person: their subscription package needs online programming " <>
        "(`online_programming`) or personal training (`personal_training`), ADR-232. " <>
        "`class_visits` (ADR-805, members): the package lets them book classes, so a WOD of " <>
        "their own on a day without a booking uses one class visit instead.",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"User profile shell", "application/json",
         %Schema{type: :object, additionalProperties: true}},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  operation(:finance,
    summary: "Get a user's finance dossier section",
    parameters: [@id_parameter],
    responses: [ok: {"Finance profile", "application/json", @finance_response}]
  )

  operation(:training_history,
    summary: "Get a user's executions, scores, assignments, and class participation",
    parameters: [@id_parameter],
    responses: [ok: {"Training history", "application/json", @training_response}]
  )

  operation(:schedule,
    summary: "Get a role-specific user schedule",
    parameters: [
      @id_parameter,
      %Parameter{
        name: :start_date,
        in: :query,
        required: true,
        schema: %Schema{type: :string, format: :date}
      },
      %Parameter{
        name: :end_date,
        in: :query,
        required: true,
        schema: %Schema{type: :string, format: :date}
      }
    ],
    responses: [ok: {"User schedule", "application/json", @schedule_response}]
  )

  operation(:program_workout,
    summary:
      "Copy or save a workout and associate it with this user's assignment, class variant or booked class",
    description:
      "Athletes receive a personal assignment. Members follow `mode` (ADR-125). " <>
        "Without folder_id, copies are filed automatically (ADR-136): athletes in their " <>
        "folder, class workouts in the class-day folder, member variations in the " <>
        "member's variations folder. " <>
        "Athletes need a package with online programming or personal training (ADR-232); " <>
        "otherwise 403 `programming_not_in_package`. A member's `personal` WOD (ADR-805) " <>
        "needs a class booked that day or one class visit of the package for that day (the " <>
        "assignment uses it), else online programming; otherwise 403 `member_wod_not_covered`. " <>
        "A class_variant (ADR-785) needs none and is refused with 422 `class_variant_closed` once the class ended.",
    parameters: [@id_parameter],
    request_body: @program_body,
    responses: [created: {"Programming result", "application/json", @summary_object}]
  )

  operation(:program_workout_for_users,
    summary: "Program the same workout for several people at once (ADR-201)",
    description:
      "Each person in `user_ids` is programmed exactly as `POST /users/{id}/programming` " <>
        "would program them alone: the same checks (client scope, mode, booked class, " <>
        "personal-programming grant), their own copy and their own folder. The answer lists " <>
        "one result per person; one person failing does not undo the others.",
    request_body: @program_many_body,
    responses: [
      ok: {"One result per person", "application/json", @program_many_response},
      unprocessable_entity: {"No people or too many", "application/json", @summary_object}
    ]
  )

  @role_names Enum.map(Palee.Organizations.roles(), &to_string/1)
  @role_list %Schema{type: :array, items: %Schema{type: :string, enum: @role_names}}

  @change_roles_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          properties: %{
            user_ids: %Schema{
              type: :array,
              items: %Schema{type: :string, format: :uuid},
              minItems: 1,
              maxItems: Palee.Application.ChangeClientRoles.max_users()
            },
            add: @role_list,
            remove: @role_list
          },
          required: [:user_ids]
        }
      }
    }
  }

  @change_roles_response %Schema{
    type: :object,
    required: [:results],
    properties: %{
      results: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          required: [:user_id, :status, :roles],
          properties: %{
            user_id: %Schema{type: :string, format: :uuid},
            status: %Schema{
              type: :string,
              enum: ["changed", "unchanged", "preview", "refused"]
            },
            roles: %Schema{
              type: :array,
              items: %Schema{type: :string, enum: @role_names},
              description: "The roles after the change (preview: would be; refused: as they are)."
            },
            code: %Schema{type: :string, description: "Why the person was refused."},
            impact: %Schema{
              type: :object,
              required: [:future_bookings],
              properties: %{
                future_bookings: %Schema{type: :integer, minimum: 0},
                kept_package: %Schema{
                  type: :object,
                  nullable: true,
                  required: [:name],
                  properties: %{
                    name: %Schema{type: :string, nullable: true},
                    ends_on: %Schema{type: :string, format: :date, nullable: true}
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  operation(:preview_client_roles,
    summary: "Preview a change of box roles of one or many clients (ADR-812)",
    description:
      "Nothing changes. Each result carries the roles the person would have and the impact: " <>
        "future bookings that would be cancelled and the running package that stays to its end.",
    request_body: @change_roles_body,
    responses: [
      ok: {"One result per person", "application/json", @change_roles_response},
      forbidden: {"No right to change roles", "application/json", @summary_object},
      unprocessable_entity:
        {"No people, too many or no roles", "application/json", @summary_object}
    ]
  )

  operation(:change_client_roles,
    summary: "Change the box roles of one or many clients (ADR-812)",
    description:
      "Each person's roles become their current roles plus `add` minus `remove`, through the " <>
        "same checks as `PUT /users/{id}/roles`. The new roles must keep a buyer role (member, " <>
        "athlete or guest). One person failing does not undo the others.",
    request_body: @change_roles_body,
    responses: [
      ok: {"One result per person", "application/json", @change_roles_response},
      forbidden: {"No right to change roles", "application/json", @summary_object},
      unprocessable_entity:
        {"No people, too many or no roles", "application/json", @summary_object}
    ]
  )

  operation(:place_in_class,
    summary:
      "Book a member into a class, optionally moving them out of an upcoming booking in one transaction (ADR-232)",
    parameters: [@id_parameter],
    request_body: @class_placement_body,
    responses: [created: {"Class placement result", "application/json", @summary_object}]
  )

  operation(:place_on_waitlist,
    summary: "Put a member on a full class's waitlist (ADR-790)",
    description:
      "Staff of the class's branch put an active member on the waitlist of a future, full class, " <>
        "at the end or first in line. The package is checked as for a staff placement; when a " <>
        "place opens the entry is booked and approved at once. The member is notified.",
    parameters: [@id_parameter],
    request_body: @class_waitlist_body,
    responses: [
      created:
        {"Waitlist entry", "application/json",
         %Schema{
           type: :object,
           required: [:booking, :waitlist_position],
           properties: %{
             booking: %Schema{type: :object, additionalProperties: true},
             waitlist_position: %Schema{type: :integer, nullable: true}
           }
         }}
    ]
  )

  @placement_class %Schema{
    type: :object,
    additionalProperties: false,
    required: [
      :blocked_reason,
      :capacity,
      :duration_minutes,
      :name,
      :scheduled_at,
      :slot_id,
      :spots_remaining,
      :waitlist,
      :waitlist_place
    ],
    properties: %{
      slot_id: @user_id,
      name: %Schema{type: :string},
      scheduled_at: %Schema{type: :string, format: :"date-time"},
      duration_minutes: %Schema{type: :integer, nullable: true},
      capacity: %Schema{type: :integer, nullable: true},
      spots_remaining: %Schema{type: :integer},
      blocked_reason: %Schema{
        type: :string,
        nullable: true,
        description:
          "Why the class cannot take the member now, as the booking error code (slot_full, class_paused, class_not_published, already_booked, finance_*), or null."
      },
      waitlist: %Schema{
        type: :boolean,
        description:
          "ADR-790: the class is full and takes the member on its waitlist instead (not in a move)."
      },
      waitlist_place: %Schema{
        type: :integer,
        nullable: true,
        description: "ADR-790: the place «Στο τέλος» gives the member, for a waitlist class."
      }
    }
  }
  @placement_booking %Schema{
    type: :object,
    additionalProperties: false,
    required: [:booking_id, :name, :scheduled_at, :slot_id, :status],
    properties: %{
      booking_id: @user_id,
      slot_id: @user_id,
      name: %Schema{type: :string},
      scheduled_at: %Schema{type: :string, format: :"date-time"},
      status: %Schema{type: :string, enum: ["pending", "approved"]}
    }
  }
  @placement_options %Schema{
    type: :object,
    additionalProperties: false,
    required: [:bookings, :classes, :lookahead_days, :timezone],
    properties: %{
      timezone: %Schema{type: :string, description: "The box's IANA time zone (ADR-179)."},
      lookahead_days: %Schema{type: :integer},
      bookings: %Schema{type: :array, items: @placement_booking},
      classes: %Schema{type: :array, items: @placement_class}
    }
  }

  operation(:class_placement_options,
    summary: "What staff can choose when booking a member into a class or moving them (ADR-232)",
    parameters: [
      @id_parameter,
      %Parameter{
        name: :slot_id,
        in: :query,
        required: false,
        description: "ADR-790: only this class (the class page), however far away it is.",
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [ok: {"Class placement options", "application/json", @placement_options}]
  )

  operation(:prs,
    summary: "Get a user's personal records",
    parameters: [@id_parameter],
    responses: [ok: {"Personal records", "application/json", @pr_response}]
  )

  operation(:pr_members,
    summary: "Active members whose PR dossier a coach may open (ADR-132)",
    description:
      "Every coach of the gym reads members' PRs recorded here (ADR-129); coach client scope (ADR-100) does not narrow this list. Public identity only.",
    responses: [ok: {"PR dossier members", "application/json", @pr_members_response}]
  )

  operation(:incidents,
    summary: "Get a user's health and injury incidents",
    parameters: [@id_parameter],
    responses: [ok: {"Health incidents", "application/json", @collection_response}]
  )

  operation(:messages,
    summary: "Get a user's communication thread summary",
    parameters: [@id_parameter],
    responses: [ok: {"Communication summary", "application/json", @collection_response}]
  )

  operation(:coaching_context,
    summary: "Get role-aware coaching context for a user",
    parameters: [@id_parameter],
    responses: [ok: {"Coaching context", "application/json", @coaching_response}]
  )

  operation(:index_athletes,
    summary: "List assignable users (athletes; optionally members, ADR-125)",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: false,
        schema: %Schema{type: :string}
      },
      %Parameter{
        name: :include_members,
        in: :query,
        required: false,
        description:
          "Also list active members (who may receive personal programming when their package allows it).",
        schema: %Schema{type: :boolean, default: false}
      },
      PaleeWeb.Schemas.LocationScope.filter_parameter()
    ],
    responses: [
      ok:
        {"Athletes", "application/json",
         %Schema{
           type: :object,
           properties: %{
             athletes: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   nickname: %Schema{type: :string},
                   role: %Schema{type: :string}
                 },
                 required: [:id, :nickname, :role]
               }
             }
           },
           required: [:athletes]
         }}
    ]
  )

  operation(:update_role,
    summary: "Update a user's role",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        description: "User ID",
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      description: "Role params",
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              role: %Schema{
                type: :string,
                enum: ["owner", "admin", "coach", "member", "athlete"]
              }
            },
            required: [:role]
          }
        }
      }
    },
    responses: [
      ok:
        {"Updated user", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid},
             nickname: %Schema{type: :string},
             role: %Schema{type: :string}
           },
           required: [:id, :nickname, :role]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      unauthorized:
        {"Unauthorized", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      forbidden:
        {"Forbidden", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Schema{
           type: :object,
           properties: %{
             errors: %Schema{
               type: :object,
               additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
             }
           },
           required: [:errors]
         }},
      internal_server_error:
        {"Unexpected server error", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  operation(:delete,
    summary: "Delete a user's account",
    parameters: [@id_parameter],
    responses: [
      no_content: "Deleted",
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}},
      conflict:
        {"Protected history", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}},
      unprocessable_entity:
        {"Deletion blocked", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  def update_role(conn, params) do
    id = params["id"] || params[:id]
    role = Map.get(conn.body_params, "role") || Map.get(conn.body_params, :role)

    # Role is a property of the membership, not of the account (F-29): this
    # only ever changes what the target is inside the acting organization.
    case Palee.Application.ChangeMembershipRoles.set_role(
           conn.assigns.tenant_context,
           id,
           role
         ) do
      {:ok, membership} ->
        user = Palee.Identity.find_by_id(membership.user_id)

        json(conn, %{
          id: membership.user_id,
          nickname: user && user.nickname,
          role: to_string(membership.role)
        })

      error ->
        error
    end
  end

  operation(:update_roles,
    summary: "Set every role a person holds in this gym (ADR-099)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              roles: %Schema{
                type: :array,
                minItems: 1,
                items: %Schema{
                  type: :string,
                  enum:
                    Enum.map(
                      Palee.Organizations.roles(),
                      &to_string/1
                    )
                }
              }
            },
            required: [:roles]
          }
        }
      }
    },
    responses: [ok: {"Membership", "application/json", @membership_roles_response}]
  )

  def update_roles(conn, params) do
    id = params["id"] || params[:id]
    roles = Map.get(conn.body_params, :roles) || Map.get(conn.body_params, "roles")

    with {:ok, membership} <-
           Palee.Application.ChangeMembershipRoles.set_roles(
             conn.assigns.tenant_context,
             id,
             roles
           ) do
      json(conn, %{membership: membership_json(membership)})
    end
  end

  operation(:update_coach_scope,
    summary: "Make a coach a head coach (all clients) or limit them to their own (ADR-100)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{coach_scope: %Schema{type: :string, enum: ["own", "all"]}},
            required: [:coach_scope]
          }
        }
      }
    },
    responses: [ok: {"Membership", "application/json", @membership_roles_response}]
  )

  def update_coach_scope(conn, params) do
    id = params["id"] || params[:id]
    scope = Map.get(conn.body_params, :coach_scope) || Map.get(conn.body_params, "coach_scope")

    with {:ok, membership} <-
           Palee.Organizations.set_coach_scope(conn.assigns.tenant_context, id, scope) do
      json(conn, %{membership: membership_json(membership)})
    end
  end

  operation(:membership_status,
    summary: "A client's membership status without amounts (coaches, front desk)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Status", "application/json",
         %Schema{
           type: :object,
           properties: %{
             membership_status: %Schema{
               type: :object,
               properties: %{
                 status: %Schema{type: :string},
                 expires_on: %Schema{type: :string, format: :date, nullable: true},
                 frozen_until: %Schema{type: :string, format: :date, nullable: true},
                 packages: %Schema{type: :array, items: %Schema{type: :string}},
                 allowances: %Schema{type: :object, additionalProperties: true}
               },
               required: [:status, :packages, :allowances]
             }
           },
           required: [:membership_status]
         }}
    ]
  )

  def membership_status(conn, params) do
    id = params["id"] || params[:id]

    with {:ok, status} <-
           Palee.Application.GetClientMembershipStatus.call(
             conn.assigns.tenant_context,
             id
           ) do
      json(conn, %{membership_status: status})
    end
  end

  defp membership_json(membership) do
    %{
      user_id: membership.user_id,
      role: to_string(membership.role),
      roles: Enum.map(membership.roles, &to_string/1),
      coach_scope: to_string(membership.coach_scope),
      status: to_string(membership.status),
      home_location_id: membership.home_location_id
    }
  end

  def delete(conn, params) do
    admin = Guardian.Plug.current_resource(conn)

    with {:ok, _deleted} <- DeleteAdminUser.call(params["id"] || params[:id], admin.id) do
      send_resp(conn, :no_content, "")
    end
  end

  @freeze_schema %Schema{
    title: "SubscriptionFreeze",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      starts_on: %Schema{type: :string, format: :date},
      ends_on: %Schema{type: :string, format: :date},
      extension_days: %Schema{type: :integer},
      reason: %Schema{type: :string},
      admin_id: %Schema{type: :string, format: :uuid, nullable: true},
      cancelled_at: %Schema{type: :string, format: :"date-time", nullable: true},
      cancel_reason: %Schema{type: :string, nullable: true}
    },
    required: [:id, :starts_on, :ends_on, :extension_days, :reason, :cancelled_at]
  }

  @freeze_response %Schema{
    type: :object,
    properties: %{freeze: @freeze_schema},
    required: [:freeze]
  }

  operation(:freezes,
    summary: "List a member's package freezes (ADR-097)",
    parameters: [@id_parameter],
    responses: [
      ok:
        {"Freezes", "application/json",
         %Schema{
           type: :object,
           properties: %{freezes: %Schema{type: :array, items: @freeze_schema}},
           required: [:freezes]
         }}
    ]
  )

  def freezes(conn, %{id: user_id}) do
    json(conn, %{freezes: Finance.list_freezes(conn.assigns.tenant_context, user_id)})
  end

  operation(:create_freeze,
    summary: "Freeze a member's package for a date range; the package end moves out",
    parameters: [@id_parameter],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            additionalProperties: false,
            required: [:starts_on, :ends_on, :reason],
            properties: %{
              starts_on: %Schema{type: :string, format: :date},
              ends_on: %Schema{type: :string, format: :date},
              reason: %Schema{type: :string, minLength: 3, maxLength: 500},
              # ADR-760 (6A): «Να το δει και το μέλος».
              reason_shared: %Schema{type: :boolean}
            }
          }
        }
      }
    },
    responses: [
      created: {"Freeze", "application/json", @freeze_response},
      unprocessable_entity: {"Invalid freeze", "application/json", @summary_object},
      conflict: {"Overlapping freeze", "application/json", @summary_object}
    ]
  )

  def create_freeze(conn, %{id: user_id}) do
    admin = Guardian.Plug.current_resource(conn)

    with {:ok, freeze} <-
           Finance.create_freeze(
             conn.assigns.tenant_context,
             user_id,
             admin.id,
             conn.body_params
           ) do
      note_freeze(freeze)

      conn
      |> put_status(:created)
      |> json(%{freeze: freeze})
    end
  end

  # ADR-760: the dates go with the «Αρχείο ενεργειών» row.
  defp note_freeze(freeze) do
    Palee.ActivityLog.note(%{
      subject: %{"subscription_id" => freeze.membership_package_subscription_id},
      details: %{
        starts_on: Date.to_iso8601(freeze.starts_on),
        ends_on: Date.to_iso8601(freeze.ends_on),
        extension_days: freeze.extension_days
      }
    })
  end

  operation(:cancel_freeze,
    summary: "Cancel a freeze; unused days are given back",
    parameters: [
      @id_parameter,
      %Parameter{
        name: :freeze_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: false,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              reason: %Schema{type: :string, maxLength: 500, nullable: true},
              reason_shared: %Schema{type: :boolean}
            }
          }
        }
      }
    },
    responses: [
      ok: {"Freeze", "application/json", @freeze_response},
      not_found: {"Freeze not found", "application/json", @summary_object},
      conflict: {"Freeze already cancelled", "application/json", @summary_object}
    ]
  )

  def cancel_freeze(conn, %{id: user_id, freeze_id: freeze_id}) do
    with {:ok, freeze} <-
           Finance.cancel_freeze(
             conn.assigns.tenant_context,
             user_id,
             freeze_id,
             conn.body_params || %{}
           ) do
      note_freeze(freeze)
      json(conn, %{freeze: freeze})
    end
  end

  def index(conn, params) do
    with {:ok, payload} <- ListAdminUsers.call(params, conn.assigns.tenant_context) do
      json(conn, payload)
    end
  end

  def show(conn, params) do
    with {:ok, payload} <-
           GetAdminUserProfile.call(
             params["id"] || params[:id],
             conn.assigns.tenant_context,
             tenant_organization_slug(conn)
           ) do
      json(conn, payload)
    end
  end

  defp tenant_organization_slug(conn) do
    case conn.assigns[:tenant_context] do
      %{organization: %{slug: slug}} -> slug
      _missing -> nil
    end
  end

  def finance(conn, params) do
    with {:ok, payload} <-
           GetAdminUserFinance.call(
             params["id"] || params[:id],
             conn.assigns.tenant_context,
             tenant_organization_slug(conn)
           ) do
      json(conn, payload)
    end
  end

  def training_history(conn, params),
    do: render_service(conn, GetAdminUserTrainingHistory, params)

  def schedule(conn, params) do
    with {:ok, payload} <-
           GetAdminUserSchedule.call(
             conn.assigns.tenant_context,
             params["id"] || params[:id],
             params["start_date"] || params[:start_date],
             params["end_date"] || params[:end_date]
           ) do
      json(conn, payload)
    end
  end

  def program_workout(conn, params) do
    admin = Guardian.Plug.current_resource(conn)

    with {:ok, payload} <-
           ProgramUserWorkout.call(
             conn.assigns.tenant_context,
             admin,
             params["id"] || params[:id],
             conn.body_params
           ) do
      conn |> put_status(:created) |> json(payload)
    end
  end

  def program_workout_for_users(conn, _params) do
    admin = Guardian.Plug.current_resource(conn)
    body = conn.body_params

    with {:ok, payload} <-
           ProgramWorkoutForUsers.call(
             conn.assigns.tenant_context,
             admin,
             body[:user_ids] || body["user_ids"],
             body
           ) do
      json(conn, payload)
    end
  end

  def preview_client_roles(conn, _params), do: client_roles(conn, true)

  def change_client_roles(conn, _params), do: client_roles(conn, false)

  defp client_roles(conn, dry_run?) do
    with {:ok, payload} <-
           Palee.Application.ChangeClientRoles.call(
             conn.assigns.tenant_context,
             conn.body_params,
             dry_run?
           ) do
      json(conn, payload)
    end
  end

  def place_in_class(conn, params) do
    with {:ok, payload} <-
           PlaceMemberInClass.call(
             conn.assigns.tenant_context,
             params["id"] || params[:id],
             conn.body_params
           ) do
      conn |> put_status(:created) |> json(payload)
    end
  end

  def place_on_waitlist(conn, params) do
    with {:ok, payload} <-
           PlaceMemberOnWaitlist.call(
             conn.assigns.tenant_context,
             params["id"] || params[:id],
             conn.body_params
           ) do
      conn |> put_status(:created) |> json(payload)
    end
  end

  def class_placement_options(conn, params) do
    with {:ok, payload} <-
           GetClassPlacementOptions.call(
             conn.assigns.tenant_context,
             params["id"] || params[:id],
             slot_id: blank_to_nil(params["slot_id"] || params[:slot_id])
           ) do
      json(conn, payload)
    end
  end

  def prs(conn, params), do: render_service(conn, GetAdminUserPRs, params)

  def pr_members(conn, _params) do
    with {:ok, payload} <- ListPRDossierMembers.call(conn.assigns.tenant_context) do
      json(conn, payload)
    end
  end

  def incidents(conn, params) do
    with {:ok, payload} <-
           GetAdminUserIncidents.call(conn.assigns.tenant_context, params["id"] || params[:id]) do
      json(conn, payload)
    end
  end

  def messages(conn, params), do: render_service(conn, GetAdminUserMessages, params)

  def coaching_context(conn, params) do
    id = params["id"] || params[:id]

    with {:ok, payload} <-
           GetAdminUserCoachingContext.call(conn.assigns.tenant_context, id, params) do
      json(conn, payload)
    end
  end

  def index_athletes(conn, params) do
    opts = [
      include_members: truthy?(params["include_members"] || params[:include_members]),
      location_ids: Palee.Organizations.requested_location_ids(params)
    ]

    case ListAthletes.call(conn.assigns.tenant_context, params["q"] || params[:q], opts) do
      {:error, reason} -> {:error, reason}
      athletes -> json(conn, %{athletes: athletes})
    end
  end

  defp truthy?(value), do: value in [true, "true", "1"]

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp render_service(conn, service, params) do
    with {:ok, payload} <- service.call(conn.assigns.tenant_context, params["id"] || params[:id]) do
      json(conn, payload)
    end
  end
end
