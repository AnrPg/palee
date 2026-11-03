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
          mine: %Schema{review() | title: "MyBoxReview", nullable: true},
          can_review: %Schema{type: :boolean, description: "Checked in at least once"}
        }),
      required: [:average, :can_review, :count, :google, :has_more, :mine, :reviews]
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
