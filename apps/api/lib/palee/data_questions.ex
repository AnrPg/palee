defmodule Palee.DataQuestions do
  @moduledoc """
  AI questions over a box's data (ADR-361): staff ask in plain words; a
  model picks typed, permission-checked read queries from a catalogue, runs
  them under the box's row-level security and the asker's rights, and
  answers citing the numbers. Every question is kept in an audit log.
  """

  alias Palee.DataQuestions.{BoxDataReader, QuestionStore}

  alias Palee.DataQuestions.Domain.{
    AnswerPolicy,
    Catalogue,
    Grounding,
    Prompt,
    ResultShape
  }

  defdelegate queries(), to: Catalogue
  defdelegate query_names(), to: Catalogue, as: :names
  defdelegate periods(), to: Catalogue
  defdelegate fetch_query(name), to: Catalogue, as: :fetch
  defdelegate available_queries(capabilities), to: Catalogue, as: :available
  defdelegate query_allowed?(query, capabilities), to: Catalogue, as: :allowed?
  defdelegate input_schema(query), to: Catalogue
  defdelegate resolve_arguments(query, args, today), to: Catalogue, as: :resolve

  defdelegate model_content(ref, query, params, raw), to: ResultShape, as: :for_model
  defdelegate result_table(ref, query, raw), to: ResultShape, as: :table
  defdelegate result_people(query, raw), to: ResultShape, as: :people
  defdelegate result_numbers(content), to: ResultShape, as: :numbers

  defdelegate unsupported_numbers(answer, allowed), to: Grounding, as: :unsupported
  defdelegate numbers_in(text), to: Grounding

  defdelegate system_prompt(facts), to: Prompt, as: :system
  defdelegate answer_schema(), to: Prompt
  defdelegate prompt_version(), to: Prompt, as: :version

  defdelegate validate_question(text), to: AnswerPolicy, as: :question
  defdelegate evaluate_answer(json, known_refs), to: AnswerPolicy, as: :evaluate

  defdelegate run_query(context, name, params, zone), to: BoxDataReader, as: :run
  defdelegate record(context, attrs), to: QuestionStore, as: :insert
  defdelegate get(context, id), to: QuestionStore
  defdelegate list(context, filters), to: QuestionStore
  defdelegate count_since(context, user_id, since), to: QuestionStore

  # ADR-117 reviewed tenant export/purge.
  def tenant_data_policy, do: Palee.DataQuestions.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
