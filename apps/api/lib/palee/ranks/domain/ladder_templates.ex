defmodule Palee.Ranks.Domain.LadderTemplates do
  @moduledoc """
  The catalogue of ready-made ladders («Πρότυπα», ADR-377, ADR-400): belts,
  kyu, khan, grades and levels researched per sport, each rank with the
  skills a coach ticks and the minimum days or classes a federation states.

  A template is only a starting point: the box (or solo coach) copies it
  into its own ladder and changes levels, skills and requirements freely.
  `source` says whether the levels are a federation's or school's system
  (`federation`) or Palee's own levels built from the researched skills
  where no official levels exist (`palee`).

  Texts are English message ids of the `rank_templates` gettext domain;
  `LadderPolicy.localize_template/2` turns them into the box's language.
  Keys never change: a template key may be sent by older clients.
  """

  alias __MODULE__.{Combat, Dance, Fitness, Gymnastics, Outdoor}

  @doc "Every template, in picker order (by family)."
  def all, do: Combat.all() ++ Gymnastics.all() ++ Fitness.all() ++ Dance.all() ++ Outdoor.all()
end
