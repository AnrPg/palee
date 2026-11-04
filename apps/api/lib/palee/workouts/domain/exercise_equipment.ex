defmodule Palee.Workouts.Domain.ExerciseEquipment do
  @moduledoc """
  ADR-542: what each exercise of the canonical catalogue
  (`WorkoutDsl.ExerciseCatalog`, the list the WOD editor and the exercise
  suggestions use) needs, as stable equipment keys.

  The map sits beside the catalogue instead of inside its entries, so the
  catalogue can grow (ADR-461 approved additions, new entries) without
  touching this file, and this file without touching the catalogue.

  No invented defaults: an exercise that can be done with different kit
  (a goblet squat with a kettlebell or a dumbbell, a lunge with or without
  load) or that is not listed here is **unknown** (`:unknown`), never
  `none`. `none` means the movement needs nothing (an air squat, a burpee).
  """

  # The vocabulary, in display order. Keys never change meaning; the web
  # holds their labels (`Equipment.<key>`, English and Greek).
  @keys ~w(none barbell dumbbell kettlebell bench box pull_up_bar rings dip_bars climbing_rope
           ghd jump_rope wall_ball sled rower bike air_bike ski_erg pool band foam_roller)

  @barbell ~w(back-squat front-squat overhead-squat deadlift sumo-deadlift romanian-deadlift
              stiff-leg-deadlift clean power-clean hang-clean clean-and-jerk snatch power-snatch
              hang-snatch muscle-snatch jerk push-jerk push-press strict-press floor-press
              barbell-row pendlay-row good-morning hip-thrust thruster)

  @none ~w(air-squat pistol-squat wall-sit glute-bridge push-up hand-release-push-up
           diamond-push-up sit-up v-up hollow-hold arch-hold plank side-plank burpee broad-jump
           handstand-hold handstand-walk handstand-push-up wall-walk run sprint jumping-jack
           mountain-climber bear-crawl hip-flexor-stretch hamstring-stretch quad-stretch
           calf-stretch pigeon-stretch couch-stretch child-pose downward-dog cat-cow
           thoracic-rotation)

  @pull_up_bar ~w(pull-up strict-pull-up chest-to-bar-pull-up chin-up bar-muscle-up toes-to-bar
                  knees-to-elbows)

  @by_exercise Map.merge(
                 Map.new(@barbell, &{&1, ["barbell"]}),
                 Map.merge(
                   Map.new(@none, &{&1, ["none"]}),
                   Map.new(@pull_up_bar, &{&1, ["pull_up_bar"]})
                 )
               )
               |> Map.merge(%{
                 "box-squat" => ["barbell", "box"],
                 "bench-press" => ["barbell", "bench"],
                 "incline-bench-press" => ["barbell", "bench"],
                 "dumbbell-bench-press" => ["dumbbell", "bench"],
                 "dumbbell-row" => ["dumbbell"],
                 "lateral-raise" => ["dumbbell"],
                 "devil-press" => ["dumbbell"],
                 "man-maker" => ["dumbbell"],
                 "step-up" => ["box"],
                 "box-jump" => ["box"],
                 "box-jump-over" => ["box"],
                 "burpee-box-jump" => ["box"],
                 "sled-push" => ["sled"],
                 "sled-pull" => ["sled"],
                 "kettlebell-swing" => ["kettlebell"],
                 "american-kettlebell-swing" => ["kettlebell"],
                 "russian-kettlebell-swing" => ["kettlebell"],
                 "turkish-get-up" => ["kettlebell"],
                 "wall-ball" => ["wall_ball"],
                 "dip" => ["dip_bars"],
                 "ring-dip" => ["rings"],
                 "ring-row" => ["rings"],
                 "ring-muscle-up" => ["rings"],
                 "rope-climb" => ["climbing_rope"],
                 "legless-rope-climb" => ["climbing_rope"],
                 "ghd-sit-up" => ["ghd"],
                 "double-under" => ["jump_rope"],
                 "single-under" => ["jump_rope"],
                 "row" => ["rower"],
                 "bike" => ["bike"],
                 "air-bike" => ["air_bike"],
                 "ski-erg" => ["ski_erg"],
                 "swim" => ["pool"],
                 "band-pull-apart" => ["band"],
                 "foam-roll" => ["foam_roller"]
               })

  @doc "The equipment keys, in display order."
  def keys, do: @keys

  @doc "Whether `key` is a vocabulary key."
  def key?(key), do: key in @keys

  @doc """
  What a catalogue exercise needs: a list of keys (`["none"]` when it needs
  nothing) or `:unknown`.
  """
  def for_exercise(id) when is_binary(id), do: Map.get(@by_exercise, id, :unknown)
  def for_exercise(_id), do: :unknown

  @doc "Catalogue id => keys, for every exercise whose equipment is known."
  def export, do: @by_exercise

  @doc "Sorts keys by the vocabulary order (unknown keys last, by name)."
  def sort(keys) do
    order = @keys |> Enum.with_index() |> Map.new()
    Enum.sort_by(keys, &{Map.get(order, &1, length(@keys)), &1})
  end
end
