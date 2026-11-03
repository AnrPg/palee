"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { batchRankSkill, classSkillsKey, fetchClassSkills, readyRanksKey, type ClassSkills } from "@/api/body-devices";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { rankSkills } from "@/lib/body-devices";

export type ClassPerson = { userId: string; name: string };

type SkillChoice = { value: string; rankId: string; skillId: string; label: string; ladder: string };

/** Every skill of every ladder that has an id, as «Ladder › Rank: skill». */
export function classSkillChoices(data: ClassSkills | undefined): { ladder: string; options: SkillChoice[] }[] {
  return (data?.ladders ?? [])
    .filter((ladder) => ladder && Array.isArray(ladder.ranks))
    .map((ladder) => ({
      ladder: ladder.name,
      options: ladder.ranks.flatMap((rank) =>
        rankSkills(rank)
          .filter((skill) => skill.id)
          .map((skill) => ({ value: `${rank.id}:${skill.id}`, rankId: rank.id, skillId: skill.id!, label: `${rank.name}: ${skill.name}`, ladder: ladder.name })),
      ),
    }))
    .filter((group) => group.options.length > 0);
}

/** Who may get the skill: the coach reaches them and the skill's rank is the one they work towards. */
export function eligibility(person: ClassSkills["people"][number] | undefined, choice: SkillChoice | null): "ok" | "notYours" | "otherRank" {
  if (!person || !person.reachable) return "notYours";
  if (!choice || !Array.isArray(person.next_rank_ids) || !person.next_rank_ids.includes(choice.rankId)) return "otherRank";
  return "ok";
}

/**
 * Mockup «Ο coach τσεκάρει», option Β: in a class the coach picks one skill
 * and ticks it for several people at once. Only people working towards
 * that skill's rank can get it; nothing shows at a box without skills.
 */
export function ClassSkillTicks({ token, slug, people }: { token: string; slug: string; people: ClassPerson[] }) {
  const t = useTranslations("BodyDevices");
  const [open, setOpen] = useState(false);
  const ids = useMemo(() => people.map((person) => person.userId).sort(), [people]);
  const data = useQuery({
    queryKey: classSkillsKey(slug, ids),
    enabled: Boolean(token && slug && ids.length > 0),
    queryFn: () => fetchClassSkills(token, slug, ids),
    retry: false,
  });
  const groups = classSkillChoices(data.data);
  if (ids.length === 0 || groups.length === 0) return null;
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="min-h-11 self-start rounded-2xl px-4 text-sm font-semibold"
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        data-testid="class-skill-open"
      >
        {t("ranks.class.open")}
      </button>
      {open && data.data ? <ClassSkillSheet token={token} slug={slug} people={people} data={data.data} groups={groups} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

function ClassSkillSheet({
  token,
  slug,
  people,
  data,
  groups,
  onClose,
}: {
  token: string;
  slug: string;
  people: ClassPerson[];
  data: ClassSkills;
  groups: ReturnType<typeof classSkillChoices>;
  onClose: () => void;
}) {
  const t = useTranslations("BodyDevices");
  const queryClient = useQueryClient();
  const [value, setValue] = useState("");
  const choice = groups.flatMap((group) => group.options).find((option) => option.value === value) ?? null;
  const byUser = new Map(data.people.filter((person) => person && typeof person.user_id === "string").map((person) => [person.user_id, person]));
  const ticked = (userId: string) =>
    Boolean(choice && (byUser.get(userId)?.checked ?? []).some((entry) => entry.rank_id === choice.rankId && entry.skill_id === choice.skillId));
  const [selected, setSelected] = useState<Set<string> | null>(null);
  const current = selected ?? new Set(people.filter((person) => ticked(person.userId)).map((person) => person.userId));
  const save = useMutation({
    mutationFn: async () => {
      if (!choice) return;
      const add = people.filter((person) => current.has(person.userId) && !ticked(person.userId)).map((person) => person.userId);
      const remove = people.filter((person) => !current.has(person.userId) && ticked(person.userId)).map((person) => person.userId);
      if (add.length) await batchRankSkill(token, slug, { rank_id: choice.rankId, skill_id: choice.skillId, user_ids: add });
      if (remove.length) await batchRankSkill(token, slug, { rank_id: choice.rankId, skill_id: choice.skillId, user_ids: remove, checked: false });
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["body-devices", "class-skills", slug] });
      void queryClient.invalidateQueries({ queryKey: ["body-devices", "client-ranks", slug] });
      void queryClient.invalidateQueries({ queryKey: readyRanksKey(slug) });
      onClose();
    },
  });

  return (
    <Dialog
      onClose={onClose}
      title={t("ranks.class.title")}
      titleId="class-skill-sheet"
      variant="sheet"
      size="md"
      testId="class-skill-sheet"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <button type="button" onClick={onClose} className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("cancel")}
          </button>
          <button
            type="button"
            disabled={!choice || save.isPending}
            onClick={() => save.mutate()}
            className="min-h-11 rounded-2xl px-5 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("save")}
          </button>
        </div>
      }
    >
      <div className="flex flex-col gap-3">
        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("ranks.class.skill")}
          <Select
            value={value}
            onValueChange={(next) => {
              setValue(next);
              setSelected(null);
            }}
            className="min-h-11"
          >
            <option value="" disabled>
              {t("ranks.class.pick")}
            </option>
            {groups.map((group) => (
              <optgroup key={group.ladder} label={group.ladder}>
                {group.options.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </optgroup>
            ))}
          </Select>
        </label>
        {choice ? (
          <ul className="flex flex-col" aria-label={t("ranks.class.people")}>
            {people.map((person, index) => {
              const status = eligibility(byUser.get(person.userId), choice);
              const on = current.has(person.userId);
              return (
                <li key={person.userId} style={index === 0 ? undefined : { borderTop: "1px solid var(--border)" }}>
                  <button
                    type="button"
                    aria-pressed={on}
                    disabled={status !== "ok"}
                    onClick={() => {
                      const next = new Set(current);
                      if (on) next.delete(person.userId);
                      else next.add(person.userId);
                      setSelected(next);
                    }}
                    className="flex min-h-12 w-full items-center gap-3 py-2 text-start disabled:opacity-60"
                  >
                    <span
                      aria-hidden="true"
                      className="grid h-5 w-5 shrink-0 place-items-center rounded-md text-xs font-bold"
                      style={{ background: on ? "var(--success)" : "transparent", color: "var(--primary-contrast)", border: `1px solid ${on ? "var(--success)" : "var(--border)"}` }}
                    >
                      {on ? "✓" : ""}
                    </span>
                    <span className="flex min-w-0 flex-col">
                      <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{person.name}</span>
                      {status !== "ok" ? (
                        <span className="text-xs" style={{ color: "var(--dim)" }}>{t(status === "notYours" ? "ranks.class.notYours" : "ranks.class.otherRank")}</span>
                      ) : null}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        ) : null}
        {save.isError ? <ErrorNotice variant="field">{t("ranks.tick.failed")}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
