defmodule Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog do
  @moduledoc """
  Versioned canonical exercise registry used by Quick Text resolution and
  autocomplete.

  Identifiers are stable slugs. Labels and aliases may evolve, but an existing
  identifier is never reassigned to another movement.
  """

  @strength_capabilities ~w(
    sets reps load target-rpe target-rir tempo side stance grip
    range-of-motion equipment rest progression percentage-of variation
    interval-assignment score-contribution transition-time
  )
  @bodyweight_capabilities ~w(
    sets reps duration load target-rpe target-rir tempo side grip
    range-of-motion equipment rest progression percentage-of variation
    interval-assignment score-contribution transition-time
  )
  @cardio_capabilities ~w(
    sets duration distance calories pace cadence target-heart-rate incline
    resistance equipment rest interval-assignment variation score-contribution
    transition-time
  )
  @mobility_capabilities ~w(
    sets reps duration side range-of-motion equipment rest target-rpe variation
    interval-assignment score-contribution transition-time
  )
  @skill_capabilities ~w(
    sets reps duration target-rpe tempo side grip range-of-motion equipment
    rest progression interval-assignment variation score-contribution
    transition-time
  )

  @entries [
    {"air-squat", "Air Squat", :bodyweight, ["Bodyweight Squat"]},
    {"back-squat", "Back Squat", :strength, ["Barbell Back Squat"]},
    {"front-squat", "Front Squat", :strength, ["Barbell Front Squat"]},
    {"overhead-squat", "Overhead Squat", :strength, ["OHS"]},
    {"goblet-squat", "Goblet Squat", :strength, []},
    {"box-squat", "Box Squat", :strength, []},
    {"split-squat", "Split Squat", :strength, []},
    {"bulgarian-split-squat", "Bulgarian Split Squat", :strength,
     ["Rear-foot Elevated Split Squat"]},
    {"pistol-squat", "Pistol Squat", :bodyweight, ["Pistol"]},
    {"wall-sit", "Wall Sit", :bodyweight, []},
    {"deadlift", "Deadlift", :strength, ["Conventional Deadlift"]},
    {"sumo-deadlift", "Sumo Deadlift", :strength, []},
    {"romanian-deadlift", "Romanian Deadlift", :strength, ["RDL"]},
    {"stiff-leg-deadlift", "Stiff-leg Deadlift", :strength, []},
    {"single-leg-deadlift", "Single-leg Deadlift", :strength, []},
    {"clean", "Clean", :strength, ["Squat Clean"]},
    {"power-clean", "Power Clean", :strength, []},
    {"hang-clean", "Hang Clean", :strength, []},
    {"clean-and-jerk", "Clean and Jerk", :strength, ["C&J"]},
    {"snatch", "Snatch", :strength, ["Squat Snatch"]},
    {"power-snatch", "Power Snatch", :strength, []},
    {"hang-snatch", "Hang Snatch", :strength, []},
    {"muscle-snatch", "Muscle Snatch", :strength, []},
    {"jerk", "Jerk", :strength, ["Split Jerk"]},
    {"push-jerk", "Push Jerk", :strength, []},
    {"push-press", "Push Press", :strength, []},
    {"strict-press", "Strict Press", :strength, ["Shoulder Press", "Overhead Press"]},
    {"bench-press", "Bench Press", :strength, ["Barbell Bench Press"]},
    {"incline-bench-press", "Incline Bench Press", :strength, []},
    {"floor-press", "Floor Press", :strength, []},
    {"dumbbell-bench-press", "Dumbbell Bench Press", :strength, ["DB Bench Press"]},
    {"dumbbell-row", "Dumbbell Row", :strength, ["One-arm Dumbbell Row"]},
    {"barbell-row", "Barbell Row", :strength, ["Bent-over Row"]},
    {"pendlay-row", "Pendlay Row", :strength, []},
    {"upright-row", "Upright Row", :strength, []},
    {"good-morning", "Good Morning", :strength, []},
    {"hip-thrust", "Hip Thrust", :strength, []},
    {"glute-bridge", "Glute Bridge", :bodyweight, []},
    {"lunge", "Lunge", :strength, ["Forward Lunge"]},
    {"reverse-lunge", "Reverse Lunge", :strength, []},
    {"walking-lunge", "Walking Lunge", :strength, []},
    {"step-up", "Step-up", :strength, ["Box Step-up"]},
    {"calf-raise", "Calf Raise", :strength, []},
    {"biceps-curl", "Biceps Curl", :strength, []},
    {"triceps-extension", "Triceps Extension", :strength, []},
    {"skull-crusher", "Skull Crusher", :strength, []},
    {"lateral-raise", "Lateral Raise", :strength, []},
    {"front-raise", "Front Raise", :strength, []},
    {"face-pull", "Face Pull", :strength, []},
    {"farmer-carry", "Farmer Carry", :strength, ["Farmer's Carry"]},
    {"front-rack-carry", "Front Rack Carry", :strength, []},
    {"overhead-carry", "Overhead Carry", :strength, []},
    {"sled-push", "Sled Push", :strength, []},
    {"sled-pull", "Sled Pull", :strength, []},
    {"kettlebell-swing", "Kettlebell Swing", :strength, ["KB Swing"]},
    {"american-kettlebell-swing", "American Kettlebell Swing", :strength, []},
    {"russian-kettlebell-swing", "Russian Kettlebell Swing", :strength, []},
    {"turkish-get-up", "Turkish Get-up", :strength, ["TGU"]},
    {"thruster", "Thruster", :strength, []},
    {"wall-ball", "Wall Ball", :bodyweight, ["Wall Ball Shot"]},
    {"devil-press", "Devil Press", :strength, []},
    {"man-maker", "Man Maker", :strength, []},
    {"push-up", "Push-up", :bodyweight, ["Pushup"]},
    {"hand-release-push-up", "Hand-release Push-up", :bodyweight, ["HR Push-up"]},
    {"diamond-push-up", "Diamond Push-up", :bodyweight, []},
    {"dip", "Dip", :bodyweight, ["Parallel Bar Dip"]},
    {"ring-dip", "Ring Dip", :bodyweight, []},
    {"pull-up", "Pull-up", :bodyweight, ["Pullup"]},
    {"strict-pull-up", "Strict Pull-up", :bodyweight, []},
    {"chest-to-bar-pull-up", "Chest-to-bar Pull-up", :bodyweight, ["C2B"]},
    {"chin-up", "Chin-up", :bodyweight, []},
    {"ring-row", "Ring Row", :bodyweight, []},
    {"muscle-up", "Muscle-up", :skill, ["Muscle Up"]},
    {"ring-muscle-up", "Ring Muscle-up", :skill, ["RMU"]},
    {"bar-muscle-up", "Bar Muscle-up", :skill, ["BMU"]},
    {"rope-climb", "Rope Climb", :skill, []},
    {"legless-rope-climb", "Legless Rope Climb", :skill, []},
    {"toes-to-bar", "Toes-to-bar", :bodyweight, ["TTB", "Toes to Bar"]},
    {"knees-to-elbows", "Knees-to-elbows", :bodyweight, ["K2E"]},
    {"sit-up", "Sit-up", :bodyweight, ["Situp"]},
    {"ghd-sit-up", "GHD Sit-up", :bodyweight, ["GHD"]},
    {"v-up", "V-up", :bodyweight, []},
    {"hollow-hold", "Hollow Hold", :bodyweight, []},
    {"arch-hold", "Arch Hold", :bodyweight, []},
    {"plank", "Plank", :bodyweight, ["Front Plank"]},
    {"side-plank", "Side Plank", :bodyweight, []},
    {"pallof-press", "Pallof Press", :strength, []},
    {"back-extension", "Back Extension", :bodyweight, ["Hip Extension"]},
    {"burpee", "Burpee", :bodyweight, []},
    {"burpee-box-jump", "Burpee Box Jump", :bodyweight, []},
    {"box-jump", "Box Jump", :bodyweight, []},
    {"box-jump-over", "Box Jump-over", :bodyweight, []},
    {"broad-jump", "Broad Jump", :bodyweight, []},
    {"double-under", "Double-under", :skill, ["DU", "Double Under"]},
    {"single-under", "Single-under", :skill, ["Single Under"]},
    {"handstand-hold", "Handstand Hold", :skill, []},
    {"handstand-walk", "Handstand Walk", :skill, ["HS Walk"]},
    {"handstand-push-up", "Handstand Push-up", :skill, ["HSPU"]},
    {"wall-walk", "Wall Walk", :skill, []},
    {"run", "Run", :cardio, ["Running"]},
    {"sprint", "Sprint", :cardio, []},
    {"row", "Row", :cardio, ["Rower", "Concept2 Row"]},
    {"bike", "Bike", :cardio, ["Cycling"]},
    {"air-bike", "Air Bike", :cardio, ["Assault Bike", "Echo Bike"]},
    {"ski-erg", "Ski Erg", :cardio, ["SkiErg"]},
    {"swim", "Swim", :cardio, ["Swimming"]},
    {"stair-climb", "Stair Climb", :cardio, ["Stair Climber"]},
    {"jumping-jack", "Jumping Jack", :cardio, []},
    {"mountain-climber", "Mountain Climber", :cardio, []},
    {"bear-crawl", "Bear Crawl", :cardio, []},
    {"hip-flexor-stretch", "Hip Flexor Stretch", :mobility, []},
    {"hamstring-stretch", "Hamstring Stretch", :mobility, []},
    {"quad-stretch", "Quadriceps Stretch", :mobility, ["Quad Stretch"]},
    {"calf-stretch", "Calf Stretch", :mobility, []},
    {"pigeon-stretch", "Pigeon Stretch", :mobility, []},
    {"couch-stretch", "Couch Stretch", :mobility, []},
    {"child-pose", "Child's Pose", :mobility, ["Child Pose"]},
    {"downward-dog", "Downward Dog", :mobility, []},
    {"cat-cow", "Cat-Cow", :mobility, []},
    {"thoracic-rotation", "Thoracic Rotation", :mobility, ["T-spine Rotation"]},
    {"shoulder-dislocate", "Shoulder Dislocate", :mobility, ["Pass-through"]},
    {"band-pull-apart", "Band Pull-apart", :mobility, []},
    {"foam-roll", "Foam Roll", :mobility, ["Foam Rolling"]}
  ]

  # ADR-461: search-only aliases on top of each entry's own (which stay
  # unambiguous for Quick Text resolution): common abbreviations and the
  # Greek names members type. Suggestions match them; `resolve/1` does not.
  @search_aliases %{
    "air-squat" => ["Σκουάτ", "Καθίσματα", "Squat"],
    "back-squat" => ["Σκουάτ πλάτης", "Πίσω σκουάτ", "BS"],
    "front-squat" => ["Μπροστινό σκουάτ", "FS"],
    "overhead-squat" => ["Σκουάτ πάνω από το κεφάλι"],
    "deadlift" => ["Άρσεις θανάτου", "Ντεντλιφτ", "DL"],
    "romanian-deadlift" => ["Ρουμανικές άρσεις"],
    "sumo-deadlift" => ["Σούμο ντεντλιφτ", "SDL"],
    "clean-and-jerk" => ["CJ", "C and J", "Κλιν εν τζερκ", "Ζετέ"],
    "snatch" => ["Αρασέ", "Σνατς"],
    "clean" => ["Κλιν"],
    "power-clean" => ["PC"],
    "power-snatch" => ["PS"],
    "jerk" => ["Τζερκ"],
    "push-press" => ["PP"],
    "strict-press" => ["Πιέσεις ώμων", "OHP"],
    "bench-press" => ["Πιέσεις πάγκου", "Πάγκος", "BP"],
    "barbell-row" => ["Κωπηλατική με μπάρα"],
    "dumbbell-row" => ["Κωπηλατική με αλτήρα"],
    "hip-thrust" => ["Γλουτιαία γέφυρα με μπάρα"],
    "glute-bridge" => ["Γέφυρα γλουτών"],
    "lunge" => ["Προβολές", "Λάντζες"],
    "walking-lunge" => ["Προβολές με περπάτημα"],
    "biceps-curl" => ["Κάμψεις δικεφάλων"],
    "kettlebell-swing" => ["Αιωρήσεις", "Σουίνγκ", "KBS"],
    "thruster" => ["Θράστερ"],
    "wall-ball" => ["Γουόλ μπολ", "WB"],
    "push-up" => ["Κάμψεις", "Πους απ"],
    "dip" => ["Βυθίσεις", "Ντιπς"],
    "pull-up" => ["Έλξεις", "Πουλ απ", "PU"],
    "chin-up" => ["Έλξεις υπτιασμένες"],
    "chest-to-bar-pull-up" => ["CTB"],
    "muscle-up" => ["Μασλ απ", "MU"],
    "rope-climb" => ["Σχοινί", "Αναρρίχηση σχοινιού"],
    "toes-to-bar" => ["T2B"],
    "knees-to-elbows" => ["KTE"],
    "sit-up" => ["Κοιλιακοί", "Σιτ απ"],
    "plank" => ["Σανίδα", "Πλανκ"],
    "side-plank" => ["Πλάγια σανίδα"],
    "back-extension" => ["Ραχιαίοι", "Υπερεκτάσεις"],
    "burpee" => ["Μπέρπι", "Μπέρπις"],
    "box-jump" => ["Άλματα σε κουτί", "BJ"],
    "broad-jump" => ["Άλμα μήκους"],
    "double-under" => ["Διπλό σχοινάκι", "Ντάμπλ αντερ"],
    "single-under" => ["Σχοινάκι"],
    "handstand-push-up" => ["Κατακόρυφες κάμψεις"],
    "handstand-walk" => ["Περπάτημα στα χέρια"],
    "handstand-hold" => ["Κατακόρυφος"],
    "run" => ["Τρέξιμο"],
    "sprint" => ["Σπριντ"],
    "row" => ["Κωπηλατική", "Κωπηλατικό"],
    "bike" => ["Ποδήλατο"],
    "air-bike" => ["Assault", "Ποδήλατο αέρα"],
    "swim" => ["Κολύμπι"],
    "jumping-jack" => ["Αναπηδήσεις"],
    "mountain-climber" => ["Ορειβάτες"],
    "bear-crawl" => ["Αρκουδάκι"],
    "farmer-carry" => ["Μεταφορά αγρότη"],
    "turkish-get-up" => ["Τούρκικο σήκωμα"],
    "calf-raise" => ["Γάμπες"],
    "good-morning" => ["Γκουντ μόρνινγκ"],
    "foam-roll" => ["Ρολό"]
  }

  @capabilities %{
    "strength" => @strength_capabilities,
    "bodyweight" => @bodyweight_capabilities,
    "cardio" => @cardio_capabilities,
    "mobility" => @mobility_capabilities,
    "skill" => @skill_capabilities
  }

  @catalog Enum.map(@entries, fn {id, label, category, aliases} ->
             capabilities = Map.fetch!(@capabilities, Atom.to_string(category))

             %{
               id: id,
               label: label,
               category: Atom.to_string(category),
               aliases: aliases,
               capabilities: capabilities
             }
           end)

  def entries, do: @catalog

  @doc "ADR-461: the capabilities of an entry of `category` (an approved addition's)."
  def capabilities_for(category), do: Map.get(@capabilities, category, [])

  @doc """
  ADR-461: the export with the Palee team's approved additions
  (`%{kind, catalog_slug, label, category}`): new entries appended, aliases
  joined to their entry's.
  """
  def export(additions) do
    aliases =
      additions
      |> Enum.filter(&(&1.kind == "alias"))
      |> Enum.group_by(& &1.catalog_slug, & &1.label)

    added =
      for %{kind: "entry"} = addition <- additions do
        %{
          id: addition.catalog_slug,
          label: addition.label,
          category: addition.category,
          aliases: [],
          capabilities: capabilities_for(addition.category)
        }
      end

    Enum.map(export() ++ added, fn entry ->
      %{entry | aliases: entry.aliases ++ Map.get(aliases, entry.id, [])}
    end)
  end

  @doc "ADR-461: the entry's search-only aliases (suggestions match them, `resolve/1` does not)."
  def search_aliases(id), do: Map.get(@search_aliases, id, [])

  def resolve(name) when is_binary(name) do
    normalized = normalize_name(name)

    exact = Enum.filter(@catalog, &(normalize_name(&1.label) == normalized))

    case exact do
      [entry] ->
        {:ok, entry, :canonical}

      [] ->
        aliases =
          Enum.filter(@catalog, fn entry ->
            Enum.any?(entry.aliases, &(normalize_name(&1) == normalized))
          end)

        case aliases do
          [entry] -> {:ok, entry, :alias}
          [] -> {:error, :not_found}
          entries -> {:error, {:ambiguous, Enum.map(entries, & &1.id)}}
        end

      entries ->
        {:error, {:ambiguous, Enum.map(entries, & &1.id)}}
    end
  end

  def resolve(_name), do: {:error, :not_found}

  def fetch(id) when is_binary(id), do: Enum.find(@catalog, &(&1.id == id))
  def fetch(_id), do: nil

  def supports?(entry_or_id, capability) do
    entry =
      if is_map(entry_or_id),
        do: entry_or_id,
        else: fetch(to_string(entry_or_id))

    is_map(entry) and to_string(capability) in entry.capabilities
  end

  def export do
    Enum.map(@catalog, &Map.take(&1, [:id, :label, :category, :aliases, :capabilities]))
  end

  defp normalize_name(name) do
    name
    |> String.normalize(:nfc)
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[\s_-]+/u, " ")
  end
end
