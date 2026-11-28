defmodule Palee.Application.ClassPlacementAccess do
  @moduledoc """
  Who may put a member into a class or on its waitlist (ADR-232, ADR-790).

    * Staff who book for clients or manage the schedule (owner, office,
      front desk): any member they reach with that capability (ADR-100), in
      classes of their own branches (ADR-186).
    * A coach (ADR-790, ANR pick δ): in the classes they run, from the class
      page («+ Προσθήκη»). A head coach (`run_classes: :all`) in any class of
      their branches.

  `class_id` is nil for the profile's list of choices, which only staff of
  the first kind open.
  """

  alias Palee.Application.{AuthorizeClientAccess, ClassLocation}
  alias Palee.{Organizations, Scheduling}

  @booking_capabilities [:book_for_clients, :manage_schedule]

  @doc "`:ok`, or why the actor may not place `user_id` in `class_id`."
  def authorize(context, user_id, class_id) do
    cond do
      books_for_clients?(context) -> books_for(context, user_id, class_id)
      is_binary(class_id) -> runs_class(context, class_id)
      true -> {:error, :forbidden}
    end
  end

  defp books_for_clients?(context),
    do: Enum.any?(@booking_capabilities, &Organizations.capability_scope(context, &1))

  defp books_for(context, user_id, class_id) do
    client? =
      Enum.any?(@booking_capabilities, &(AuthorizeClientAccess.call(context, &1, user_id) == :ok))

    cond do
      not client? -> {:error, :not_your_client}
      is_nil(class_id) -> :ok
      true -> ClassLocation.authorize_class(context, class_id)
    end
  end

  defp runs_class(context, class_id) do
    case Organizations.capability_scope(context, :run_classes) do
      :all ->
        ClassLocation.authorize_class(context, class_id)

      :own ->
        case Scheduling.get_slot(context, class_id) do
          %{coach_user_id: coach_id} when coach_id == context.user_id -> :ok
          %{} -> {:error, :forbidden}
          nil -> {:error, :not_found}
        end

      _none ->
        {:error, :forbidden}
    end
  end
end
