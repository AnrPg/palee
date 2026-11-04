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
  defdelegate template(key), to: LadderPolicy
  defdelegate localize_template(template, translate), to: LadderPolicy
  defdelegate cast_ranks(ranks, scale_levels), to: LadderPolicy
  defdelegate assign_skill_ids(ranks, existing), to: LadderPolicy
  defdelegate cast_ready_criteria(criteria, default), to: LadderPolicy
  defdelegate skill_entries(rank), to: LadderPolicy
  defdelegate find_skill(rank, skill_id, skill), to: LadderPolicy

  # Promotions.
  defdelegate current_award(awards), to: PromotionPolicy, as: :current
  defdelegate next_rank(ranks, current_rank), to: PromotionPolicy
  defdelegate progress(next, since, attended, today), to: PromotionPolicy
  defdelegate progress(next, since, attended, today, checked), to: PromotionPolicy
  defdelegate progress(next, since, attended, today, checked, criteria), to: PromotionPolicy
  defdelegate count_attended(history, class_type_ids, since), to: PromotionPolicy

  defdelegate validate_award(rank, stripes, skills, current_rank, current_stripes, on, today),
    to: PromotionPolicy

  defdelegate listed_skill?(rank, skill), to: PromotionPolicy
  defdelegate certificate_number(award_id, date), to: PromotionPolicy
  defdelegate certificate_pdf(view, fonts), to: CertificatePdf, as: :render
  defdelegate diploma_role(roles, coach_scope), to: CertificatePdf, as: :role_label

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
  defdelegate list_skill_checks(user_id), to: RankStore
  defdelegate put_skill_check(attrs), to: RankStore
  defdelegate delete_skill_check(user_id, rank_id, skill_id), to: RankStore
  defdelegate list_skill_checks_for(user_ids), to: RankStore
  defdelegate list_awards_for(user_ids), to: RankStore
  defdelegate list_unnotified_checks(user_id), to: RankStore
  defdelegate mark_checks_notified(ids, now), to: RankStore

  defdelegate skill_notice(checks, ranks_by_id),
    to: Palee.Ranks.Domain.SkillNoticePolicy,
    as: :notice

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
