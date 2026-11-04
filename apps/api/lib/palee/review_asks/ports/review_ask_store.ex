defmodule Palee.ReviewAsks.Ports.ReviewAskStore do
  @moduledoc "Persistence of review asks (ADR-355); every callback takes the tenant context first."

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback get_settings(context()) :: map() | nil
  @callback save_settings(context(), map(), lock_version :: non_neg_integer()) ::
              {:ok, map()} | {:error, :stale | term()}
  @callback list_asks(context(), user_id :: id()) :: [map()]
  @callback insert_ask(context(), map()) :: {:ok, map()} | {:error, :already_asked | term()}
  @callback get_ask(context(), id(), user_id :: id()) :: map() | nil
  @callback update_ask(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback opted_out?(context(), user_id :: id()) :: boolean()
  @callback opt_out(context(), user_id :: id(), DateTime.t()) :: :ok
  @callback opt_in(context(), user_id :: id()) :: :ok
  @callback summary(context(), since :: DateTime.t()) :: %{atom() => non_neg_integer()}

  # ADR-386: in-app reviews.
  @callback get_review(context(), user_id :: id()) :: map() | nil
  @callback get_review_by_id(context(), id()) :: map() | nil
  @callback save_review(context(), user_id :: id(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_review(context(), user_id :: id()) :: :ok
  @callback list_reviews(context(), %{limit: pos_integer(), offset: non_neg_integer()}) :: [map()]
  @callback review_stats(context()) :: %{count: non_neg_integer(), sum: non_neg_integer()}
  @callback reply_review(context(), id(), map()) :: {:ok, map()} | {:error, term()}

  # ADR-397: reports on reviews and the Palee team's decisions.
  @callback reported_review_ids(context(), reporter_id :: id()) :: [id()]
  @callback count_reports_since(context(), reporter_id :: id(), DateTime.t()) :: non_neg_integer()
  @callback insert_report(context(), map()) :: {:ok, map()} | {:error, :already_reported | term()}
  @callback latest_decision(context(), review_id :: id()) :: map() | nil
  @callback decide_review(
              context(),
              review_id :: id(),
              review_changes :: map(),
              map(),
              String.t()
            ) ::
              {:ok, %{review: map(), decision: map(), reports: [map()]}}
              | {:error, :box_review_not_found | :review_report_decided | term()}
  @callback restore_review(context(), review_id :: id(), review_changes :: map(), map()) ::
              {:ok, %{review: map(), decision: map()}}
              | {:error, :box_review_not_found | :review_not_hidden | term()}
  @callback platform_open_reports(context(), limit :: pos_integer()) :: [map()]
  @callback platform_decisions(context(), limit :: pos_integer()) :: [map()]
  @callback platform_review_organization(context(), review_id :: id()) :: id() | nil
  # The daily job: no session, through SECURITY DEFINER functions.
  @callback purge_removed_texts(before :: DateTime.t()) :: non_neg_integer()
  @callback open_report_totals() :: %{
              reviews: non_neg_integer(),
              reports: non_neg_integer(),
              oldest: DateTime.t() | nil
            }

  # ADR-387: the Google listing snapshot.
  @callback get_place_snapshot(context()) :: map() | nil
  @callback save_place_snapshot(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback place_due_organizations(DateTime.t()) :: [id()]
end
