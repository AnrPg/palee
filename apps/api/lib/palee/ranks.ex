defmodule Palee.Ranks do
  @moduledoc """
  Ranks bounded context (ADR-377, CP-E2): belts and levels a box defines
  per discipline, the promotions its coaches give, and the diplomas. The
  ladder's discipline is a workout type (ADR-275); a rank may suggest one
  of the box's scale levels (ADR-128). Rules live in the domain; use cases
  in `Palee.Application.RankLadders`, `RankPromotions` and `MyRanks`.
  """

  alias Palee.Ranks.Domain.{CertificatePdf, LadderPolicy, PromotionPolicy, TenantDataPolicy}
  alias Palee.Ranks.RankStore

  defdelegate with_context(context, fun), to: RankStore

  # Vocabulary and ladders.
  defdelegate styles(), to: LadderPolicy
  defdelegate colors(), to: LadderPolicy
  defdelegate disciplines(), to: LadderPolicy
  defdelegate discipline_family(discipline), to: LadderPolicy, as: :family
  defdelegate templates(), to: LadderPolicy
  defdelegate cast_ranks(ranks, scale_levels), to: LadderPolicy

  # Promotions.
  defdelegate current_award(awards), to: PromotionPolicy, as: :current
  defdelegate next_rank(ranks, current_rank), to: PromotionPolicy
  defdelegate progress(next, since, attended, today), to: PromotionPolicy
  defdelegate count_attended(history, class_type_ids, since), to: PromotionPolicy

  defdelegate validate_award(rank, stripes, skills, current_rank, current_stripes, on, today),
    to: PromotionPolicy

  defdelegate certificate_number(award_id, date), to: PromotionPolicy
  defdelegate certificate_pdf(view, fonts), to: CertificatePdf, as: :render

  # Store.
  defdelegate list_ladders(), to: RankStore
  defdelegate get_ladder(id), to: RankStore
  defdelegate insert_ladder(attrs, ranks), to: RankStore
  defdelegate update_ladder(ladder, attrs, ranks), to: RankStore
  defdelegate archive_ladder(ladder, now), to: RankStore
  defdelegate list_awards(user_id), to: RankStore
  defdelegate get_award(id), to: RankStore
  defdelegate insert_award(attrs), to: RankStore
  defdelegate revoke_award(award, attrs), to: RankStore

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
