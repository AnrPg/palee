/**
 * Offline mirror of the API's muscle tree
 * (`Palee.Anatomy.Domain.MuscleTaxonomy`, ADR-163): region -> group ->
 * head, each group and head carrying the Terminologia Anatomica 2 ids of the
 * atlas meshes that draw it (ADR-164, nodes `ta2-<id>.<l|r|m>`).
 *
 * The API module is the source of truth; `taxonomy.test.ts` parses it and
 * fails when this copy drifts. When `GET /api/anatomy/taxonomy` exists, its
 * answer wins and this stays the offline fallback. Display names are
 * translated through `Anatomy.muscle.<id>`; `name` is the English reference.
 */

export type MuscleNodeKind = "region" | "group" | "head";

export type MuscleNodeId = string;

export type MuscleNode = {
  id: MuscleNodeId;
  kind: MuscleNodeKind;
  name: string;
  parentId: MuscleNodeId | null;
  regionId: MuscleNodeId;
  groupId: MuscleNodeId | null;
  ta2Ids: readonly string[];
};

type HeadTuple = readonly [id: string, name: string, ta2Ids: readonly string[]];
type GroupTuple = readonly [id: string, name: string, ta2Ids: readonly string[], heads: readonly HeadTuple[]];
type RegionTuple = readonly [id: string, name: string, groups: readonly GroupTuple[]];
export type TaxonomyTree = readonly RegionTuple[];

export const TAXONOMY_VERSION = 2;

// {region, name, [{group, name, ta2_ids, [{head, name, ta2_ids}]}]}, as in the API module.
export const TAXONOMY_TREE: TaxonomyTree = [
  ["neck", "Neck", [
    ["sternocleidomastoid", "Sternocleidomastoid", ["2156"], []],
    ["scalenes", "Scalenes", [], [
      ["scalenus-anterior", "Anterior scalene", ["2152"]],
      ["scalenus-medius", "Middle scalene", ["2153"]],
      ["scalenus-posterior", "Posterior scalene", ["2154"]],
    ]],
    ["deep-neck-flexors", "Deep neck flexors", [], [
      ["longus-colli", "Longus colli", ["2148"]],
      ["longus-capitis", "Longus capitis", ["2149"]],
      ["rectus-capitis", "Rectus capitis, anterior and lateral", ["2150", "2151"]],
    ]],
    ["splenius", "Splenius", [], [
      ["splenius-capitis", "Splenius capitis", ["2273"]],
      ["splenius-cervicis", "Splenius cervicis", ["2274"]],
    ]],
    ["semispinalis", "Semispinalis", [], [
      ["semispinalis-capitis", "Semispinalis capitis", ["2283"]],
      ["semispinalis-cervicis", "Semispinalis cervicis", ["2282"]],
      ["semispinalis-thoracis", "Semispinalis thoracis", ["2281"]],
    ]],
    ["suboccipitals", "Suboccipital muscles", ["2249", "2250", "2251", "2252"], []],
  ]],
  ["shoulders", "Shoulders", [
    ["deltoid", "Deltoid", [], [
      ["deltoid-anterior", "Anterior deltoid", ["2453"]],
      ["deltoid-lateral", "Lateral deltoid", ["2454"]],
      ["deltoid-posterior", "Posterior deltoid", ["2455"]],
    ]],
    ["rotator-cuff", "Rotator cuff", [], [
      ["supraspinatus", "Supraspinatus", ["2457"]],
      ["infraspinatus", "Infraspinatus", ["2458"]],
      ["teres-minor", "Teres minor", ["2459"]],
      ["subscapularis", "Subscapularis", ["2460"]],
    ]],
  ]],
  ["chest", "Chest", [
    ["pectoralis-major", "Pectoralis major", [], [
      ["pectoralis-major-clavicular", "Clavicular head", ["2302"]],
      ["pectoralis-major-sternocostal", "Sternocostal head", ["2303"]],
      ["pectoralis-major-abdominal", "Abdominal head", ["2304"]],
    ]],
    ["pectoralis-minor", "Pectoralis minor", ["2305"], []],
    ["serratus-anterior", "Serratus anterior", ["2307"], []],
    ["subclavius", "Subclavius", ["2306"], []],
  ]],
  ["upper-back", "Upper back", [
    ["trapezius", "Trapezius", [], [
      ["trapezius-upper", "Upper trapezius", ["2227"]],
      ["trapezius-middle", "Middle trapezius", ["2228"]],
      ["trapezius-lower", "Lower trapezius", ["2229"]],
    ]],
    ["rhomboids", "Rhomboids", [], [
      ["rhomboid-major", "Rhomboid major", ["2232"]],
      ["rhomboid-minor", "Rhomboid minor", ["2233"]],
    ]],
    ["levator-scapulae", "Levator scapulae", ["2234"], []],
    ["latissimus-dorsi", "Latissimus dorsi", ["2231"], []],
    ["teres-major", "Teres major", ["2462"], []],
    ["serratus-posterior", "Serratus posterior", [], [
      ["serratus-posterior-superior", "Serratus posterior superior", ["2236"]],
      ["serratus-posterior-inferior", "Serratus posterior inferior", ["2235"]],
    ]],
  ]],
  ["lower-back", "Lower back", [
    ["erector-spinae", "Erector spinae", [], [
      ["iliocostalis", "Iliocostalis", ["2258", "2260", "2261"]],
      ["longissimus", "Longissimus", ["2263", "2265", "2266"]],
      ["spinalis", "Spinalis", ["2268", "2269", "2270"]],
    ]],
    ["multifidus", "Multifidus", ["2277", "2278", "2279"], []],
    ["short-back-muscles", "Short segmental back muscles", [], [
      ["rotatores", "Rotatores", ["2284", "2285", "2289"]],
      ["interspinales", "Interspinales", ["2291", "2292", "2293"]],
      ["intertransversarii", "Intertransversarii", ["2237", "2238", "2239", "2240", "2241", "2295"]],
    ]],
    ["quadratus-lumborum", "Quadratus lumborum", ["2382"], []],
  ]],
  ["arms", "Arms", [
    ["biceps-brachii", "Biceps", [], [
      ["biceps-brachii-long", "Long head", ["2465"]],
      ["biceps-brachii-short", "Short head", ["2466"]],
    ]],
    ["brachialis", "Brachialis", ["2469"], []],
    ["coracobrachialis", "Coracobrachialis", ["2468"], []],
    ["triceps-brachii", "Triceps", [], [
      ["triceps-brachii-long", "Long head", ["2472"]],
      ["triceps-brachii-lateral", "Lateral head", ["2473"]],
      ["triceps-brachii-medial", "Medial head", ["2474"]],
    ]],
    ["anconeus", "Anconeus", ["2510"], []],
  ]],
  ["forearms", "Forearms", [
    ["brachioradialis", "Brachioradialis", ["2496"], []],
    ["forearm-flexors", "Wrist and finger flexors", [], [
      ["flexor-carpi-radialis", "Flexor carpi radialis", ["2481"]],
      ["palmaris-longus", "Palmaris longus", ["2482"]],
      ["flexor-carpi-ulnaris", "Flexor carpi ulnaris", ["2484", "2485"]],
      ["flexor-digitorum-superficialis", "Flexor digitorum superficialis", ["2487", "2488"]],
      ["flexor-digitorum-profundus", "Flexor digitorum profundus", ["2491"]],
      ["flexor-pollicis-longus", "Flexor pollicis longus", ["2492"]],
    ]],
    ["forearm-extensors", "Wrist and finger extensors", [], [
      ["extensor-carpi-radialis", "Extensor carpi radialis", ["2497", "2499"]],
      ["extensor-digitorum", "Finger extensors", ["2500", "2506", "2515"]],
      ["extensor-carpi-ulnaris", "Extensor carpi ulnaris", ["2508", "2509"]],
      ["thumb-extensors", "Thumb abductor and extensors", ["2516", "2517", "2518"]],
    ]],
    ["forearm-rotators", "Pronators and supinator", [], [
      ["pronator-teres", "Pronator teres", ["2479", "2480"]],
      ["pronator-quadratus", "Pronator quadratus", ["2493"]],
      ["supinator", "Supinator", ["2512"]],
    ]],
    ["hand-muscles", "Hand muscles", [], [
      ["thenar", "Thumb muscles of the hand", ["2521", "2523", "2524", "2525", "2527", "2528"]],
      ["hypothenar", "Little finger muscles of the hand", ["2520", "2529", "2530", "2531"]],
      ["interossei-hand", "Interossei of the hand", ["2534"]],
    ]],
  ]],
  ["core", "Core", [
    ["rectus-abdominis", "Rectus abdominis", ["2357"], []],
    ["obliques", "Obliques", [], [
      ["obliques-external", "External oblique", ["2364"]],
      ["obliques-internal", "Internal oblique", ["2373"]],
    ]],
    ["transversus-abdominis", "Transversus abdominis", ["2375"], []],
    ["diaphragm", "Diaphragm", ["2327"], []],
    ["intercostals", "Intercostals", [], [
      ["intercostals-external", "External intercostals", ["2311"]],
      ["intercostals-internal", "Internal intercostals", ["2312"]],
      ["intercostals-innermost", "Innermost intercostals", ["2313"]],
    ]],
    ["pelvic-floor", "Pelvic floor", [], [
      ["levator-ani", "Levator ani", ["2404", "2405", "2406"]],
      ["coccygeus", "Coccygeus", ["2412"]],
    ]],
  ]],
  ["hips", "Hips and glutes", [
    ["glutes", "Glutes", [], [
      ["gluteus-maximus", "Gluteus maximus", ["2598"]],
      ["gluteus-medius", "Gluteus medius", ["2599"]],
      ["gluteus-minimus", "Gluteus minimus", ["2600"]],
    ]],
    ["hip-flexors", "Hip flexors", [], [
      ["iliopsoas", "Iliopsoas", ["2594", "2595"]],
      ["tensor-fasciae-latae", "Tensor fasciae latae", ["2602"]],
      ["sartorius", "Sartorius", ["2610"]],
    ]],
    ["hip-rotators", "Deep hip rotators", [], [
      ["piriformis", "Piriformis", ["2604"]],
      ["obturator-internus", "Obturator internus", ["2605"]],
      ["gemelli", "Gemelli", ["2606", "2607"]],
      ["quadratus-femoris", "Quadratus femoris", ["2608"]],
      ["obturator-externus", "Obturator externus", ["2636"]],
    ]],
  ]],
  ["thighs", "Thighs", [
    ["quadriceps", "Quadriceps", [], [
      ["rectus-femoris", "Rectus femoris", ["2614"]],
      ["vastus-lateralis", "Vastus lateralis", ["2618"]],
      ["vastus-intermedius", "Vastus intermedius", ["2619"]],
      ["vastus-medialis", "Vastus medialis", ["2620"]],
    ]],
    ["hamstrings", "Hamstrings", [], [
      ["biceps-femoris-long", "Biceps femoris, long head", ["2639"]],
      ["biceps-femoris-short", "Biceps femoris, short head", ["2640"]],
      ["semitendinosus", "Semitendinosus", ["2641"]],
      ["semimembranosus", "Semimembranosus", ["2642"]],
    ]],
    ["adductors", "Adductors", [], [
      ["adductor-magnus", "Adductor magnus", ["2630", "2632"]],
      ["adductor-longus", "Adductor longus", ["2628"]],
      ["adductor-brevis", "Adductor brevis", ["2629"]],
      ["gracilis", "Gracilis", ["2635"]],
      ["pectineus", "Pectineus", ["2627"]],
    ]],
  ]],
  ["lower-legs", "Lower legs", [
    ["calves", "Calves", [], [
      ["gastrocnemius-medial", "Gastrocnemius, medial head", ["2659"]],
      ["gastrocnemius-lateral", "Gastrocnemius, lateral head", ["2658"]],
      ["soleus", "Soleus", ["2660"]],
      ["plantaris", "Plantaris", ["2663"]],
    ]],
    ["deep-calf", "Deep calf muscles", [], [
      ["tibialis-posterior", "Tibialis posterior", ["2666"]],
      ["flexor-digitorum-longus", "Flexor digitorum longus", ["2667"]],
      ["flexor-hallucis-longus", "Flexor hallucis longus", ["2668"]],
      ["popliteus", "Popliteus", ["2665"]],
    ]],
    ["tibialis-anterior", "Tibialis anterior", ["2644"], []],
    ["toe-extensors", "Long toe extensors", [], [
      ["extensor-digitorum-longus", "Extensor digitorum longus", ["2645"]],
      ["extensor-hallucis-longus", "Extensor hallucis longus", ["2650"]],
    ]],
    ["fibularis", "Fibularis", [], [
      ["fibularis-longus", "Fibularis longus", ["2652"]],
      ["fibularis-brevis", "Fibularis brevis", ["2653"]],
      ["fibularis-tertius", "Fibularis tertius", ["2649"]],
    ]],
  ]],
  ["feet", "Feet", [
    ["foot-muscles", "Foot muscles", [], [
      ["foot-dorsal", "Muscles on top of the foot", ["2670", "2671"]],
      ["big-toe-muscles", "Big toe muscles of the sole", ["2672", "2674", "2675", "2677", "2678"]],
      ["little-toe-muscles", "Little toe muscles of the sole", ["2679", "2681", "2682"]],
      ["central-sole", "Central sole muscles", ["2683", "2684", "2685"]],
    ]],
  ]],
];

/** Every node in tree order (region, then its groups, each followed by its heads). */
export function buildNodes(tree: TaxonomyTree): MuscleNode[] {
  return tree.flatMap(([regionId, regionName, groups]) => {
    const groupNodes = groups.flatMap(([groupId, groupName, groupTa2, heads]) => {
      const headNodes: MuscleNode[] = heads.map(([headId, headName, headTa2]) => ({
        id: headId,
        kind: "head",
        name: headName,
        parentId: groupId,
        regionId,
        groupId,
        ta2Ids: headTa2,
      }));
      const group: MuscleNode = {
        id: groupId,
        kind: "group",
        name: groupName,
        parentId: regionId,
        regionId,
        groupId,
        ta2Ids: [...groupTa2, ...headNodes.flatMap((head) => head.ta2Ids)],
      };
      return [group, ...headNodes];
    });
    const region: MuscleNode = {
      id: regionId,
      kind: "region",
      name: regionName,
      parentId: null,
      regionId,
      groupId: null,
      ta2Ids: groupNodes.filter((node) => node.kind === "group").flatMap((node) => node.ta2Ids),
    };
    return [region, ...groupNodes];
  });
}

export const MUSCLE_NODES: readonly MuscleNode[] = buildNodes(TAXONOMY_TREE);

const BY_ID = new Map(MUSCLE_NODES.map((node) => [node.id, node]));
const CHILDREN = new Map<string, MuscleNode[]>();
for (const node of MUSCLE_NODES) {
  if (node.parentId) CHILDREN.set(node.parentId, [...(CHILDREN.get(node.parentId) ?? []), node]);
}

/** ta2 id -> the head (or head-less group) whose mesh it is. */
const LEAF_BY_TA2 = new Map<string, MuscleNode>();
for (const node of MUSCLE_NODES) {
  const leaf = node.kind === "head" || (node.kind === "group" && !CHILDREN.has(node.id));
  if (leaf) for (const ta2 of node.ta2Ids) LEAF_BY_TA2.set(ta2, node);
}

export function muscleNode(id: string | null | undefined): MuscleNode | undefined {
  return id ? BY_ID.get(id) : undefined;
}

export function isMuscleNodeId(id: string): boolean {
  return BY_ID.has(id);
}

export function childrenOf(id: string): MuscleNode[] {
  return CHILDREN.get(id) ?? [];
}

/** The group a target rolls up to (a group is its own group); null for regions and unknown ids. */
export function groupOf(id: string): MuscleNodeId | null {
  const node = BY_ID.get(id);
  return node && node.kind !== "region" ? node.groupId : null;
}

/** The heads of a group; a group without heads is its own single head. */
export function headsOf(groupId: string): MuscleNodeId[] {
  const heads = childrenOf(groupId);
  if (heads.length > 0) return heads.map((head) => head.id);
  return BY_ID.get(groupId)?.kind === "group" ? [groupId] : [];
}

/** The head (or head-less group) a mesh draws; undefined for meshes outside the tree. */
export function leafForTa2(ta2: string): MuscleNode | undefined {
  return LEAF_BY_TA2.get(ta2);
}
