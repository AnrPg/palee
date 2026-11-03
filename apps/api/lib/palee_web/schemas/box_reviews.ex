defmodule PaleeWeb.Schemas.BoxReviews do
  @moduledoc """
  OpenAPI schemas of the box's in-app reviews (ADR-386), its Google listing
  (ADR-387) and the website's v3.1 additions (ADR-388).
  """

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time"}
  @maybe_time %Schema{type: :string, format: :"date-time", nullable: true}
  @text %Schema{type: :string, nullable: true}
  @int %Schema{type: :integer}

  def review do
    %Schema{
      title: "BoxReview",
      type: :object,
      properties: %{
        id: @uuid,
        rating: %Schema{type: :integer, minimum: 1, maximum: 5},
        body: @text,
        author_name: %Schema{
          type: :string,
          nullable: true,
          description: "First name only; null for people who hide themselves"
        },
        created_at: @time,
        edited_at: @maybe_time,
        reply: %Schema{
          title: "BoxReviewReply",
          type: :object,
          nullable: true,
          properties: %{body: %Schema{type: :string}, replied_at: @time},
          required: [:body, :replied_at]
        }
      },
      required: [:author_name, :body, :created_at, :edited_at, :id, :rating, :reply]
    }
  end

  def google do
    %Schema{
      title: "GoogleListing",
      type: :object,
      nullable: true,
      description:
        "The box's Google rating and number of reviews, kept apart (ADR-387); " <>
          "no review texts until a legal check of Google's terms",
      properties: %{
        name: @text,
        rating: %Schema{type: :number, nullable: true},
        count: %Schema{type: :integer, nullable: true},
        maps_uri: @text,
        write_review_url: @text,
        fetched_at: @time
      },
      required: [:count, :fetched_at, :maps_uri, :name, :rating, :write_review_url]
    }
  end

  defp listing_properties do
    %{
      count: @int,
      average: %Schema{type: :number, nullable: true},
      reviews: %Schema{type: :array, items: review()},
      has_more: %Schema{type: :boolean},
      google: google()
    }
  end

  def staff_response do
    %Schema{
      title: "BoxReviewsResponse",
      type: :object,
      properties: listing_properties(),
      required: [:average, :count, :google, :has_more, :reviews]
    }
  end

  def member_response do
    %Schema{
      title: "MyBoxReviewsResponse",
      type: :object,
      properties:
        Map.merge(listing_properties(), %{
          mine: my_review(),
          can_review: %Schema{type: :boolean, description: "Checked in at least once"},
          reported_ids: %Schema{
            type: :array,
            items: @uuid,
            description: "Reviews I reported that the Palee team has not decided yet (ADR-397)"
          }
        }),
      required: [
        :average,
        :can_review,
        :count,
        :google,
        :has_more,
        :mine,
        :reported_ids,
        :reviews
      ]
    }
  end

  # ADR-397: my review, with what the Palee team decided when it hid or
  # removed it (the statement of reasons, DSA Art. 17).
  defp my_review do
    base = review()

    %Schema{
      base
      | title: "MyBoxReview",
        nullable: true,
        properties: Map.put(base.properties, :moderation, moderation()),
        required: Enum.sort([:moderation | base.required])
    }
  end

  def moderation do
    %Schema{
      title: "BoxReviewModeration",
      type: :object,
      nullable: true,
      description: "Null while the review is up; the statement of reasons when it is not",
      properties: %{
        status: %Schema{type: :string, enum: ~w(hidden removed)},
        moderated_at: @time,
        outcome: %Schema{type: :string, enum: ~w(hide remove), nullable: true},
        ground: %Schema{type: :string, nullable: true},
        legal_basis: %Schema{
          type: :string,
          enum: ~w(law terms),
          nullable: true,
          description: "The law (illegal content) or Palee's terms"
        },
        statement: @text,
        after_report: %Schema{type: :boolean, description: "Decided after a report"},
        automated: %Schema{type: :boolean, description: "Always false: a person decided"},
        decided_at: @time,
        redress: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ~w(ask_palee_again court)}
        }
      },
      required: [
        :after_report,
        :automated,
        :decided_at,
        :ground,
        :legal_basis,
        :moderated_at,
        :outcome,
        :redress,
        :statement,
        :status
      ]
    }
  end

  # ── Reports (ADR-397) ────────────────────────────────────────────────────

  @reasons ~w(offensive personal_data not_genuine spam illegal other)

  def report_request do
    %Schema{
      title: "BoxReviewReportRequest",
      type: :object,
      properties: %{
        reason: %Schema{type: :string, enum: @reasons},
        note: %Schema{
          type: :string,
          nullable: true,
          maxLength: 500,
          description: "Required for illegal and other"
        }
      },
      required: [:reason]
    }
  end

  def report_response do
    %Schema{
      title: "BoxReviewReportResponse",
      type: :object,
      description: "The review stays up until the Palee team decides",
      properties: %{review_id: @uuid, status: %Schema{type: :string, enum: ["open"]}},
      required: [:review_id, :status]
    }
  end

  defp organization_ref do
    %Schema{
      title: "ReviewReportOrganization",
      type: :object,
      properties: %{id: @uuid, name: @text},
      required: [:id, :name]
    }
  end

  def platform_queue_response do
    %Schema{
      title: "PlatformReviewReportsResponse",
      type: :object,
      properties: %{
        items: %Schema{
          type: :array,
          items: %Schema{
            title: "PlatformReviewReportItem",
            type: :object,
            properties: %{
              review_id: @uuid,
              organization: organization_ref(),
              author_name: @text,
              reported: %Schema{
                title: "ReportedReviewText",
                type: :object,
                description: "The review as the latest report saw it",
                properties: %{rating: @int, body: @text},
                required: [:body, :rating]
              },
              current: %Schema{
                title: "CurrentReviewText",
                type: :object,
                nullable: true,
                properties: %{rating: @int, body: @text, edited_at: @maybe_time},
                required: [:body, :edited_at, :rating]
              },
              reports_count: @int,
              box_reported: %Schema{type: :boolean, description: "The box itself reported it"},
              reasons: %Schema{
                type: :array,
                items: %Schema{
                  title: "ReviewReportReasonCount",
                  type: :object,
                  properties: %{reason: %Schema{type: :string}, count: @int},
                  required: [:count, :reason]
                }
              },
              notes: %Schema{
                type: :array,
                items: %Schema{
                  title: "ReviewReportNote",
                  type: :object,
                  properties: %{
                    reason: %Schema{type: :string},
                    role: %Schema{type: :string, enum: ~w(member box)},
                    note: %Schema{type: :string},
                    at: @time
                  },
                  required: [:at, :note, :reason, :role]
                }
              },
              first_reported_at: @time
            },
            required: [
              :author_name,
              :box_reported,
              :current,
              :first_reported_at,
              :notes,
              :organization,
              :reasons,
              :reported,
              :reports_count,
              :review_id
            ]
          }
        },
        decisions: %Schema{
          type: :array,
          items: %Schema{
            title: "PlatformReviewDecision",
            type: :object,
            properties: %{
              id: @uuid,
              review_id: %Schema{type: :string, format: :uuid, nullable: true},
              organization: organization_ref(),
              outcome: %Schema{type: :string, enum: ~w(keep hide remove)},
              ground: %Schema{type: :string},
              statement: @text,
              reports_count: @int,
              decided_by: @text,
              decided_at: @time
            },
            required: [
              :decided_at,
              :decided_by,
              :ground,
              :id,
              :organization,
              :outcome,
              :reports_count,
              :review_id,
              :statement
            ]
          }
        }
      },
      required: [:decisions, :items]
    }
  end

  def decision_request do
    %Schema{
      title: "PlatformReviewDecisionRequest",
      type: :object,
      properties: %{
        outcome: %Schema{type: :string, enum: ~w(keep hide remove)},
        ground: %Schema{
          type: :string,
          enum: ["no_violation" | @reasons],
          nullable: true,
          description: "no_violation for keep; a report reason for hide and remove"
        },
        statement: %Schema{
          type: :string,
          nullable: true,
          maxLength: 1000,
          description: "What the author reads; required for hide and remove"
        }
      },
      required: [:outcome]
    }
  end

  def decision_response do
    %Schema{
      title: "PlatformReviewDecisionResponse",
      type: :object,
      properties: %{
        review_id: @uuid,
        outcome: %Schema{type: :string},
        ground: %Schema{type: :string},
        resolved: %Schema{type: :integer, description: "Open reports this decision closed"}
      },
      required: [:ground, :outcome, :resolved, :review_id]
    }
  end

  def review_request do
    %Schema{
      title: "BoxReviewRequest",
      type: :object,
      properties: %{
        rating: %Schema{type: :integer, minimum: 1, maximum: 5},
        body: %Schema{type: :string, nullable: true, maxLength: 2000},
        locale: %Schema{type: :string, nullable: true, maxLength: 10}
      },
      required: [:rating]
    }
  end

  def reply_request do
    %Schema{
      title: "BoxReviewReplyRequest",
      type: :object,
      properties: %{body: %Schema{type: :string, minLength: 1, maxLength: 2000}},
      required: [:body]
    }
  end

  def review_response do
    %Schema{
      title: "BoxReviewResponse",
      type: :object,
      properties: %{review: review()},
      required: [:review]
    }
  end

  def places_response do
    %Schema{
      title: "GooglePlacesSearchResponse",
      type: :object,
      properties: %{
        places: %Schema{
          type: :array,
          items: %Schema{
            title: "GooglePlaceMatch",
            type: :object,
            properties: %{
              place_id: %Schema{type: :string},
              name: @text,
              address: @text,
              rating: %Schema{type: :number, nullable: true},
              rating_count: %Schema{type: :integer, nullable: true}
            },
            required: [:address, :name, :place_id, :rating, :rating_count]
          }
        }
      },
      required: [:places]
    }
  end

  # ── Website (ADR-388) ────────────────────────────────────────────────────

  def site_reviews do
    %Schema{
      title: "SiteReviews",
      type: :object,
      properties: %{
        google_reviews_url: @text,
        palee: %Schema{
          title: "SitePaleeReviews",
          type: :object,
          nullable: true,
          properties: %{
            count: @int,
            average: %Schema{type: :number, nullable: true},
            latest: %Schema{type: :array, items: review()}
          },
          required: [:average, :count, :latest]
        },
        google: google()
      },
      required: [:google, :google_reviews_url, :palee]
    }
  end

  def site_event do
    %Schema{
      title: "SiteEvent",
      type: :object,
      properties: %{
        id: @uuid,
        title: %Schema{type: :string},
        starts_at: @time,
        ends_at: @time,
        time_zone: @text,
        place_name: @text,
        price_cents: @int,
        currency: %Schema{type: :string}
      },
      required: [
        :currency,
        :ends_at,
        :id,
        :place_name,
        :price_cents,
        :starts_at,
        :time_zone,
        :title
      ]
    }
  end

  def site_wod do
    %Schema{
      title: "SiteWod",
      type: :object,
      properties: %{
        id: @uuid,
        date: %Schema{type: :string, format: :date},
        title: %Schema{type: :string},
        type: @text,
        body: @text
      },
      required: [:body, :date, :id, :title, :type]
    }
  end

  def instructions_request do
    %Schema{
      title: "SiteDomainInstructionsRequest",
      type: :object,
      properties: %{email: %Schema{type: :string, format: :email, maxLength: 160}},
      required: [:email]
    }
  end

  def instructions_response do
    %Schema{
      title: "SiteDomainInstructionsResponse",
      type: :object,
      properties: %{sent_to: %Schema{type: :string}},
      required: [:sent_to]
    }
  end

  def domain_status_response do
    %Schema{
      title: "SiteDomainStatusResponse",
      type: :object,
      description: "What the person setting up the domain sees from the emailed link",
      properties: %{
        host: %Schema{type: :string},
        status: %Schema{type: :string},
        last_error: @text,
        checked_at: @maybe_time,
        box_name: %Schema{type: :string},
        dns_records: %Schema{type: :array, items: %Schema{type: :object}}
      },
      required: [:box_name, :checked_at, :dns_records, :host, :last_error, :status]
    }
  end
end
