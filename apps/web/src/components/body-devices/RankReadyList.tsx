"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { clientRanksKey, fetchClientRanks, fetchReadyRanks, readyRanksKey, type ReadyForRank } from "@/api/body-devices";
import { Belt } from "@/components/body-devices/Belt";
import { PromoteSheet } from "@/components/body-devices/ClientRanks";
import { HubCard } from "@/components/member-app/HubParts";

/**
 * «Πληροί τις προϋποθέσεις» for the coach (ADR-400 follow-up): the people
 * (their own clients; everyone for full coaching scope) who meet what their
 * ladder counts for the next rank. A row opens the promotion sheet; the
 * promotion stays the coach's decision. Hidden when nobody is ready.
 */
export function RankReadyList({ token, slug }: { token: string; slug: string }) {
  const t = useTranslations("BodyDevices");
  const ready = useQuery({ queryKey: readyRanksKey(slug), enabled: Boolean(token && slug), queryFn: () => fetchReadyRanks(token, slug), retry: false });
  const [open, setOpen] = useState<ReadyForRank | null>(null);
  const people = (ready.data ?? []).filter((person) => person && typeof person.user_id === "string" && person.ladder && person.next);
  if (people.length === 0) return null;
  return (
    <HubCard>
      <div data-testid="rank-ready-list">
        <h3 className="mb-1 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {t("ranks.readyList.title")}
        </h3>
        <ul>
          {people.map((person, index) => (
            <li key={`${person.user_id}-${person.ladder.id}`}>
              <button
                type="button"
                onClick={() => setOpen(person)}
                className="flex min-h-12 w-full items-center justify-between gap-3 py-2.5 text-start"
                style={index === 0 ? undefined : { borderTop: "1px solid var(--border)" }}
              >
                <span className="flex min-w-0 flex-col">
                  <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{person.nickname ?? t("ranks.readyList.someone")}</span>
                  <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
                    {t("ranks.readyList.line", { ladder: person.ladder.name, rank: person.next.name })}
                  </span>
                </span>
                <span className="flex shrink-0 items-center gap-2">
                  {person.ladder.style === "belt" ? <Belt color={person.next.color} className="h-2.5 w-8" /> : null}
                  <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
                </span>
              </button>
            </li>
          ))}
        </ul>
        {open ? <ReadyPromote token={token} slug={slug} person={open} onClose={() => setOpen(null)} /> : null}
      </div>
    </HubCard>
  );
}

function ReadyPromote({ token, slug, person, onClose }: { token: string; slug: string; person: ReadyForRank; onClose: () => void }) {
  const standings = useQuery({ queryKey: clientRanksKey(slug, person.user_id), queryFn: () => fetchClientRanks(token, slug, person.user_id), retry: false });
  const standing = standings.data?.ladders.find((entry) => entry?.ladder?.id === person.ladder.id);
  if (!standing) return null;
  return <PromoteSheet token={token} slug={slug} userId={person.user_id} nickname={person.nickname ?? ""} standing={standing} onClose={onClose} />;
}
