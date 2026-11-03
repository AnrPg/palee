defmodule Palee.Leads.Domain.Pipeline do
  @moduledoc """
  ADR-344: the stages of a lead («Ενδιαφερόμενος») and how it moves between
  them. Pure.

    * `new` («Νέος»): just arrived, nobody has talked to them yet;
    * `trial` («Δοκιμαστικό»): booked or came to a trial class;
    * `offer` («Προσφορά»): got a price or an offer;
    * `converted` («Έγινε μέλος»): became a box member; final, the lead stays
      as the record of how they came;
    * `lost` («Χάθηκε»): not now, with a reason. A lost lead can be reopened
      (they enquire again, or staff decide to try again).

  Any open stage may move to any other open stage (boxes do not follow a
  strict funnel), to `lost`, or to `converted`.
  """

  @stages ~w(new trial offer converted lost)
  @open_stages ~w(new trial offer)

  @sources ~w(
    website_form form join_link manual csv walk_in referral event around_me trial
    prospect_assistant
  )

  # Sources that reach the box without staff typing them in.
  @inbound_sources ~w(website_form form join_link referral event around_me trial prospect_assistant)

  @lost_reasons ~w(price schedule location no_answer chose_other not_interested other)

  def stages, do: @stages
  def open_stages, do: @open_stages
  def sources, do: @sources
  def inbound_sources, do: @inbound_sources
  def lost_reasons, do: @lost_reasons

  def open?(stage), do: stage in @open_stages

  @doc """
  The changes that move a lead from its stage to `to`, or why it cannot.
  `opts[:lost_reason]` is required for `lost`; `converted` goes through
  `convert/3`.
  """
  @spec move(map(), String.t(), DateTime.t(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def move(%{stage: from}, to, now, opts \\ []) do
    cond do
      to not in @stages -> {:error, :invalid_stage}
      from == "converted" -> {:error, :lead_converted}
      to == "converted" -> {:error, :use_convert}
      to == from -> {:error, :same_stage}
      to == "lost" -> lost(now, opts[:lost_reason])
      true -> {:ok, %{stage: to, stage_changed_at: now, lost_reason: nil}}
    end
  end

  defp lost(now, reason) when reason in @lost_reasons,
    do: {:ok, %{stage: "lost", stage_changed_at: now, lost_reason: reason}}

  defp lost(_now, _reason), do: {:error, :invalid_lost_reason}

  @doc "The changes that record a lead becoming a box member as `user_id`."
  @spec convert(map(), binary(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def convert(%{stage: "converted"}, _user_id, _now), do: {:error, :lead_converted}

  def convert(_lead, user_id, now) when is_binary(user_id),
    do:
      {:ok,
       %{
         stage: "converted",
         stage_changed_at: now,
         converted_at: now,
         user_id: user_id,
         lost_reason: nil
       }}

  @doc """
  What a new enquiry does to a lead that already exists for the same
  address: an open lead keeps its stage; a lost one is reopened as `new`.
  A converted lead is never touched (the store does not match it).
  """
  def reenquiry(%{stage: "lost"}, now),
    do: %{stage: "new", stage_changed_at: now, lost_reason: nil}

  def reenquiry(_lead, _now), do: %{}
end
