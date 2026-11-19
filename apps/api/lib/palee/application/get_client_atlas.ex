defmodule Palee.Application.GetClientAtlas do
  @moduledoc """
  `GET /api/org/:slug/staff/clients/:user_id/atlas?range=4w` (ADR-670): a
  coach opens the atlas of a WOD assigned to one athlete and sees «Η
  κάλυψη» of that athlete, node by node, in the same shape as the member's
  own atlas (ADR-164).

  The same rules as the client's Πρόοδος for coaches (ADR-165,
  `GetClientTrainingDepth`): only a coach of the gym who may see the
  client's training, only while the client is an active member, and only
  executions and log entries on a rung that reaches this gym's coaches and
  shared with it, read in the coach's tenant session so row security
  decides. Aggregates only: no entry, note or workout text.
  """

  alias Palee.Application.{GetClientTrainingDepth, GetMyAtlas}

  def call(context, client_id, params, today \\ Date.utc_today())

  def call(%{organization_id: organization_id} = context, client_id, params, today)
      when is_binary(organization_id) do
    with {:ok, client_id} <- GetClientTrainingDepth.authorize_client(context, client_id) do
      GetMyAtlas.build(context, params, today,
        user_id: client_id,
        scope: {:coach, organization_id}
      )
    end
  end

  def call(_context, _client_id, _params, _today), do: {:error, :organization_context_required}
end
