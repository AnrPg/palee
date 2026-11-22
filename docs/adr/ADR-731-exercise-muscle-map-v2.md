# ADR-731: Exercise → muscle map v2 (audit) and taxonomy v2
Date: 2026-11-22
Status: Accepted (amends ADR-163 suggestion rules, ADR-560 catalog data, ADR-551 goals strip)

## Context
A coach reviewing WOD goals said "it lists not even half of the muscles; hip thrusts: the hamstrings are prime movers; thrusters: triceps; back squat: the spinal erectors; and I'm not even naming the supporters". Two causes:

1. **What was shown.** The quiet «Στόχοι» strip (ADR-551) named only the first 3 primary groups, and the suggestion (ADR-163) dropped every stabilizer under 25 % of the workout's weight and kept at most 6. Triceps (thruster) and erector spinae (back squat) were in the data but hidden.
2. **The data.** The 2027-11-09 seed (ADR-560) mapped 891 muscle/role pairs over 123 exercises with a coarse taxonomy (91 nodes): no foot, deep calf, hand, pelvic floor or respiratory muscles, forearm flexors and extensors as one block each, hamstrings secondary in hip thrusts, triceps secondary in thrusters and presses, grip missing from many pulls.

## Decision
**Roles rubric** (one per muscle per exercise, the strongest wins):
- `primary`: prime movers of the movement's main joint actions, as listed under "muscles involved" in NSCA *Essentials of Strength Training and Conditioning* (4th ed.) and as the ExRx.net target; EMG studies where those disagree (e.g. hip thrust biceps femoris, Contreras et al. 2015, J Appl Biomech 31(6); Andersen et al. 2018).
- `secondary`: synergists doing meaningful work (ExRx synergists), plus muscles under heavy isometric load the coach expects to feel (erector spinae in squats, grip in heavy pulls, respiratory muscles in sustained conditioning).
- `stabilizer`: ExRx stabilizers, dynamic and antagonist stabilizers; heavy barbell bracing adds transversus abdominis, multifidus, diaphragm and pelvic floor (Hodges & Gandevia 2000; Hemborg et al. 1985); balance work adds the foot and deep calf muscles (Kelly et al. 2014).

Mobility drills keep their meaning: primary = stretched, secondary = stretched along, stabilizer = holds the position.

**Taxonomy v2** (`taxonomy_version` 2, 165 nodes, every mesh already in the vendored atlas, so it renders):
- Every v1 node keeps its id, kind and parent, so saved goals, journals, felt feedback and coverage from v1 stay valid with no data migration.
- Head-less groups gained heads where training cares (rhomboids, scalenes, splenius, forearm flexors ×6, extensors ×4, deep hip rotators ×5, fibularis ×3, calves + plantaris, adductor magnus + adductor minimus mesh); their meshes moved to the heads.
- New groups: deep neck flexors, semispinalis, suboccipitals, subclavius, serratus posterior, short segmental back muscles, coracobrachialis, anconeus, pronators and supinator, hand muscles, intercostals, pelvic floor, deep calf muscles, long toe extensors; new region «Feet» with foot muscles (4 heads).
- Names in all 12 languages (`Anatomy.muscle.*`), a plain «about» line per new group (`Anatomy.about.*`).

**Data**: seed `priv/repo/reference/exercise_catalog_seed_2027_11_22.json` (2,097 pairs); `Palee.Catalog` falls back to it. Migration `20271122190000_exercise_muscle_targets_v2` upserts the taxonomy and, per built-in exercise, replaces targets still equal to the 2027-11-09 seed or, when the Palee team edited them in the vendor console, folds v2 in only upwards (adds, promotes; never removes), so no edit is lost. Down restores v1 for unedited exercises.

**Suggestion**: every muscle any exercise names is kept, stabilizers included (no share threshold, no cap). Heads are still dropped when their group holds an equal or stronger role. Coverage is unchanged (stabilizers carry no volume). The goals list limit is 200 (above the taxonomy's node count; a test fails if the taxonomy outgrows it).

**Strip** (product owner's pick, 2026-11-22): one row per role, «Κύριοι», «Βοηθητικοί», «Σταθεροποίηση», naming every muscle at group level, each group once in its strongest role.

## Consequences
- WODs show many more muscles; stored goals the coach edited are not changed (ADR-671 only adds what new exercises bring).
- Exercises approved later (`origin = reviewed`) still have no targets until the Palee team maps them.
- Adding a node later: add it to the next seed, the web mirror (`lib/anatomy/taxonomy.ts`, checked by `taxonomy.test.ts`) and the 12 message files.
