"use client";

import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { SESSION_UPDATED_EVENT } from "@/api/client";
import { setTrainsWithPalee } from "@/api/profile";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { firstStaffRole, usesAppAsAthlete } from "@/lib/athlete-use";
import { useOrganizationMemberships } from "@/lib/membership-role";

/**
 * ADR-463: saves whether the person also trains with Palee and updates the
 * session at once, so the athlete prompts follow without a reload.
 */
export function useSaveTrainsWithPalee() {
  const { tokens, currentUser } = useSession();
  return useMutation({
    mutationFn: (trains: boolean) => setTrainsWithPalee(tokens!.access_token, trains),
    onSuccess: (result) => {
      if (!tokens || !currentUser) return;
      window.dispatchEvent(
        new CustomEvent(SESSION_UPDATED_EVENT, {
          detail: { tokens, currentUser: { ...currentUser, trains_with_palee: result.trains_with_palee } },
        }),
      );
    },
  });
}

/**
 * Εγώ › Ρυθμίσεις › «Προπονούμαι κι εγώ με το Palee» (ADR-463): the first-run
 * answer, for anyone with a staff role (and for anyone who said no, so it can
 * always be undone). Members and athletes never see it.
 */
export function AthleteUseSetting() {
  const t = useTranslations("Profile");
  const { currentUser } = useSession();
  const memberships = useOrganizationMemberships();
  const save = useSaveTrainsWithPalee();
  const trains = usesAppAsAthlete(currentUser);
  const staff = firstStaffRole(memberships.data) !== null;

  if (!currentUser || (!staff && trains)) return null;

  return (
    <section
      aria-labelledby="athlete-use-title"
      className="space-y-3 rounded-[2.4rem] p-8"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-center justify-between gap-4">
        <span>
          <span id="athlete-use-title" className="block text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
            {t("athleteUseTitle")}
          </span>
          <span className="mt-1 block text-sm" style={{ color: "var(--muted)" }}>{t("athleteUseDescription")}</span>
        </span>
        <button
          type="button"
          role="switch"
          aria-checked={trains}
          aria-labelledby="athlete-use-title"
          aria-describedby="athlete-use-state"
          disabled={save.isPending}
          onClick={() => save.mutate(!trains)}
          className="hit-area relative h-8 w-14 shrink-0 rounded-full disabled:opacity-60"
          style={{ background: trains ? "var(--primary)" : "var(--panel-raised)", border: "1px solid var(--border)" }}
        >
          <span
            aria-hidden="true"
            className="absolute top-1 h-5 w-5 rounded-full transition-all"
            style={{ insetInlineStart: trains ? "1.9rem" : "0.25rem", background: trains ? "var(--bg)" : "var(--text)" }}
          />
        </button>
      </div>
      <p id="athlete-use-state" className="text-sm" style={{ color: "var(--text-soft)" }}>
        {trains ? t("athleteUseOn") : t("athleteUseOff")}
      </p>
      {save.isError ? <ErrorNotice>{t("athleteUseError")}</ErrorNotice> : null}
    </section>
  );
}
