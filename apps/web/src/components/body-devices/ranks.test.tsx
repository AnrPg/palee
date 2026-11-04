import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { RankStanding } from "@/api/body-devices";

import { classSkillChoices, eligibility } from "./ClassSkillTicks";
import { ClientRanks } from "./ClientRanks";
import { draftChanges, draftOf, ladderBody, moveItem, type Draft } from "./RankLaddersSettings";
import { templateKinds } from "./RankTemplatePicker";

const fetchClientRanks = vi.fn();
const awardRank = vi.fn();
const revokeRankAward = vi.fn();
const checkRankSkill = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "el",
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${Object.values(values).join(",")}` : key),
}));
vi.mock("@/api/body-devices", () => ({
  clientRanksKey: (slug: string, userId: string) => ["body-devices", "client-ranks", slug, userId],
  fetchClientRanks: (...args: unknown[]) => fetchClientRanks(...args),
  awardRank: (...args: unknown[]) => awardRank(...args),
  revokeRankAward: (...args: unknown[]) => revokeRankAward(...args),
  checkRankSkill: (...args: unknown[]) => checkRankSkill(...args),
  readyRanksKey: (slug: string) => ["body-devices", "ready-ranks", slug],
  fetchClientDiploma: vi.fn(),
}));

const rank = (id: string, name: string, skills: string[] = []) => ({
  id,
  position: 0,
  name,
  color: "blue" as const,
  max_stripes: 4,
  requirements: skills.length ? { skills, skill_ids: skills.map((skill) => `id-${skill}`) } : {},
  scale_level_slug: null,
});

const standing: RankStanding = {
  ladder: {
    id: "l",
    name: "BJJ",
    discipline: "bjj_grappling",
    style: "belt",
    class_type_ids: [],
    ready_criteria: ["classes", "days"],
    ranks: [rank("w", "Λευκή"), rank("b", "Μπλε", ["Armbar", "Triangle"])],
  },
  current: { award_id: "a1", rank: rank("w", "Λευκή"), stripes: 2, awarded_on: "2025-03-01" },
  next: rank("b", "Μπλε", ["Armbar", "Triangle"]),
  progress: {
    rank_id: "b",
    classes: { done: 80, needed: 80 },
    days: { done: 730, needed: 730 },
    skills: ["Armbar", "Triangle"],
    skills_checked: [{ skill: "Armbar", skill_id: "id-Armbar", checked_on: "2026-10-12", note: null }],
    ready: true,
  },
  history: [],
} as RankStanding;

function renderClient() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  render(<ClientRanks token="tok" slug="box" userId="u1" nickname="Μαρία" frame={(content) => content} />, { wrapper });
}

const skill = (name: string, id: string | null = null, extras: { note?: string; video?: string } = {}) => ({
  key: id ?? `new-${name}`,
  id,
  name,
  note: extras.note ?? "",
  video: extras.video ?? "",
});

const draft = (ranks: Draft["ranks"]): Draft => ({ name: " BJJ ", discipline: "bjj_grappling", style: "belt", class_type_ids: [], ready_criteria: ["skills", "days"], ranks });

describe("ladderBody (curriculum editor, option Α)", () => {
  it("trims names, keeps skill ids, sends notes and videos only when there are any", () => {
    const body = ladderBody(
      draft([
        { key: "r1", id: "r1", name: " Λευκή ", color: "white", max_stripes: 4, min_days: null, min_classes: null, skills: [], scale_level_slug: null },
        {
          key: "r2",
          name: "Μπλε",
          color: "blue",
          max_stripes: 4,
          min_days: 730,
          min_classes: 150,
          skills: [skill(" Armbar ", "s1", { note: "Γωνία 45°" }), skill("  "), skill("Triangle")],
          scale_level_slug: "rx",
        },
      ]),
    );
    expect(body.name).toBe("BJJ");
    expect(body.ready_criteria).toEqual(["days", "skills"]);
    expect(body.ranks[0]).toEqual({ id: "r1", name: "Λευκή", color: "white", max_stripes: 4, scale_level_slug: null, requirements: {} });
    expect(body.ranks[1]).toEqual({
      name: "Μπλε",
      color: "blue",
      max_stripes: 4,
      scale_level_slug: "rx",
      requirements: { min_days: 730, min_classes: 150, skills: ["Armbar", "Triangle"], skill_ids: ["s1", null], skill_notes: ["Γωνία 45°", null] },
    });
  });
});

describe("draftChanges and moveItem (the save bar and the reordering)", () => {
  const saved = draft([{ key: "r1", id: "r1", name: "Λευκή", color: "white", max_stripes: 4, min_days: null, min_classes: null, skills: [skill("A", "a"), skill("B", "b")], scale_level_slug: null }]);

  it("counts the parts that differ and ignores the editor's own keys", () => {
    expect(draftChanges(saved, saved)).toBe(0);
    const rekeyed = { ...saved, ranks: saved.ranks.map((entry) => ({ ...entry, key: "other", skills: entry.skills.map((item) => ({ ...item, key: "x" })) })) };
    expect(draftChanges(saved, rekeyed)).toBe(0);
    const reordered = { ...saved, name: "Νέο", ranks: [{ ...saved.ranks[0], skills: moveItem(saved.ranks[0].skills, 1, 0) }] };
    expect(draftChanges(saved, reordered)).toBe(2);
  });

  it("moves an item and clamps the target", () => {
    expect(moveItem(["a", "b", "c"], 0, 2)).toEqual(["b", "c", "a"]);
    expect(moveItem(["a", "b", "c"], 2, -5)).toEqual(["c", "a", "b"]);
    const list = ["a"];
    expect(moveItem(list, 0, 1)).toBe(list);
  });

  it("reads a saved ladder into a draft with its skill ids", () => {
    const ladder = standing.ladder;
    const result = draftOf({ ...ladder, ready_criteria: [] });
    expect(result.ready_criteria).toEqual(["classes", "days"]);
    expect(result.ranks[1].skills.map((item) => [item.id, item.name])).toEqual([
      ["id-Armbar", "Armbar"],
      ["id-Triangle", "Triangle"],
    ]);
  });
});

describe("templateKinds (template picker, option Β)", () => {
  it("puts the box's own kinds first and drops malformed entries", () => {
    const templates = [
      { key: "bjj", discipline: "bjj_grappling" },
      { key: "judo", discipline: "judo" },
      { key: "bjj-kids", discipline: "bjj_grappling" },
      {},
      null,
    ];
    const { mine, rest } = templateKinds(templates, ["judo"]);
    expect(mine.map((kind) => [kind.discipline, kind.templates.length])).toEqual([["judo", 1]]);
    expect(rest.map((kind) => [kind.discipline, kind.templates.length])).toEqual([["bjj_grappling", 2]]);
  });
});

describe("class skill ticks (option Β)", () => {
  const data = {
    ladders: [{ ...standing.ladder }, { id: "empty", name: "Άδεια", ranks: [rank("x", "Χ")] }],
    people: [
      { user_id: "u1", reachable: true, next_rank_ids: ["b"], checked: [] },
      { user_id: "u2", reachable: false, next_rank_ids: ["b"], checked: [] },
      { user_id: "u3", reachable: true, next_rank_ids: ["w"], checked: [] },
    ],
  } as unknown as Parameters<typeof classSkillChoices>[0];

  it("offers every skill with an id, grouped by ladder", () => {
    const groups = classSkillChoices(data);
    expect(groups).toHaveLength(1);
    expect(groups[0].options.map((option) => option.value)).toEqual(["b:id-Armbar", "b:id-Triangle"]);
  });

  it("lets only reachable people working towards that rank get the skill", () => {
    const choice = classSkillChoices(data)[0].options[0];
    const people = data!.people;
    expect(people.map((person) => eligibility(person, choice))).toEqual(["ok", "notYours", "otherRank"]);
    expect(eligibility(undefined, choice)).toBe("notYours");
  });
});

describe("ClientRanks (mockup e2coach A)", () => {
  beforeEach(() => {
    fetchClientRanks.mockReset().mockResolvedValue({ ladders: [standing] });
    awardRank.mockReset().mockResolvedValue({});
    revokeRankAward.mockReset().mockResolvedValue({});
    checkRankSkill.mockReset().mockResolvedValue({});
  });

  it("shows «Έτοιμος» as information and pre-fills the promotion with the ticked skills", async () => {
    renderClient();
    expect(await screen.findByText("ranks.ready")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "ranks.promote" }));
    const sheet = await screen.findByTestId("promote-sheet");
    expect(within(sheet).getByRole("button", { name: /ranks.plusStripe:3/ })).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(within(sheet).getByRole("button", { name: /Μπλε/ }));
    expect(within(sheet).getByRole("button", { name: /Armbar/ })).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(within(sheet).getByRole("button", { name: "Triangle" }));
    const buttons = within(sheet).getAllByRole("button", { name: "ranks.promote" });
    fireEvent.click(buttons[buttons.length - 1]);
    await waitFor(() =>
      expect(awardRank).toHaveBeenCalledWith(
        "tok",
        "box",
        "u1",
        expect.objectContaining({ ladder_id: "l", rank_id: "b", stripes: 0, skills_checked: ["Armbar", "Triangle"] }),
      ),
    );
  });

  it("ticks a skill on the profile checklist with one tap (option Α)", async () => {
    renderClient();
    const list = await screen.findByTestId("skill-checklist");
    expect(within(list).getByText("ranks.skillsDone:1,2")).toBeInTheDocument();
    fireEvent.click(within(list).getByRole("button", { name: "Triangle" }));
    await waitFor(() => expect(checkRankSkill).toHaveBeenCalledWith("tok", "box", "u1", { rank_id: "b", skill_id: "id-Triangle", checked: true }));
  });

  it("opens the date and note for a skill from ⋯", async () => {
    renderClient();
    const list = await screen.findByTestId("skill-checklist");
    fireEvent.click(within(list).getByRole("button", { name: "ranks.tick.more:Armbar" }));
    fireEvent.click(await screen.findByRole("button", { name: "ranks.tick.untick" }));
    await waitFor(() => expect(checkRankSkill).toHaveBeenCalledWith("tok", "box", "u1", { rank_id: "b", skill_id: "id-Armbar", checked: false }));
  });

  it("asks for a reason before withdrawing an award", async () => {
    renderClient();
    fireEvent.click(await screen.findByRole("button", { name: "ranks.withdraw" }));
    const confirm = screen.getAllByRole("button", { name: "ranks.withdraw" });
    fireEvent.click(confirm[confirm.length - 1]);
    expect(screen.getByText("ranks.withdrawReasonRequired")).toBeInTheDocument();
    expect(revokeRankAward).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText(/ranks.withdrawReason/), { target: { value: "Λάθος καταχώριση" } });
    fireEvent.click(confirm[confirm.length - 1]);
    await waitFor(() => expect(revokeRankAward).toHaveBeenCalledWith("tok", "box", "a1", "Λάθος καταχώριση"));
  });
});
