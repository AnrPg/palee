defmodule Palee.Application.MyRanks do
  @moduledoc "A person's own belts and levels at a box, and their diplomas (ADR-377)."

  alias Palee.Application.{RankCertificates, RankStanding}

  def call(%{user_id: user_id} = context) do
    {:ok, %{ladders: RankStanding.call(context, user_id)}}
  end

  def certificate(%{user_id: user_id} = context, award_id),
    do: RankCertificates.call(context, award_id, user_id)
end
