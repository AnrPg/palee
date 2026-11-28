"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";

import {
  fetchClassPlacementOptions,
  placeAdminUserInClass,
  placeAdminUserOnWaitlist,
  type ClassPlacementClass,
  type WaitlistPosition,
} from "@/api/admin-users";
import { listAthletes, type AthleteOption } from "@/api/assigned-workouts";
import { ApiError } from "@/api/client";
import type { ScheduleSlot } from "@/api/schedule";
import { placementReasonKey } from "@/components/admin/users/class-placement";
import { WaitlistPositionPicker } from "@/components/schedule/WaitlistPositionPicker";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeAdminAssignmentError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const ACTIVE = new Set(["pending", "approved", "waitlisted"]);
const MAX_MATCHES = 8;

/** Members of the box who are not in the class yet (booked, asking or waiting). */
export function addableMembers(people: AthleteOption[], slot: Pick<ScheduleSlot, "bookings">): AthleteOption[] {
  const inClass = new Set(
    slot.bookings.filter((booking) => ACTIVE.has(booking.status) && !booking.guest_name).map((booking) => booking.user_id),
  );
  return people.filter((person) => person.role === "member" && !inClass.has(person.id)).slice(0, MAX_MATCHES);
}

/**
 * ADR-790 (ANR pick 1C): «+ Προσθήκη» on the staff class page. Staff (and the
 * class's coach) find a member and either book them, when the class has room
 * (approved at once, as «Κράτηση ή μετακίνηση» does), or put them on its
 * waitlist when it is full, at the end or first in line (pick 2B). The
 * server says which, and why someone cannot join, for that one class.
 */
export function AddToClassDialog({
  slot,
  accessToken,
  onClose,
  onAdded,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  onClose: () => void;
  onAdded: () => void;
}) {
  const t = useTranslations("StaffWaitlist");
  const i18n = useUiTranslations();
  const [query, setQuery] = useState("");
  const [people, setPeople] = useState<AthleteOption[]>([]);
  const [picked, setPicked] = useState<AthleteOption | null>(null);
  const [option, setOption] = useState<ClassPlacementClass | null | undefined>(undefined);
  const [position, setPosition] = useState<WaitlistPosition>("end");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (picked || !query.trim()) return;
    let active = true;
    const timer = window.setTimeout(() => {
      listAthletes(accessToken, query, { includeMembers: true })
        .then((found) => {
          if (active) setPeople(Array.isArray(found) ? found : []);
        })
        .catch(() => {
          if (active) setPeople([]);
        });
    }, 250);
    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [accessToken, picked, query]);

  useEffect(() => {
    if (!picked) return;
    let active = true;
    fetchClassPlacementOptions(accessToken, picked.id, slot.id)
      .then((result) => {
        if (active) setOption(result.classes.find((entry) => entry.slot_id === slot.id) ?? null);
      })
      .catch((reason) => {
        if (active) {
          setOption(null);
          setError(localizeAdminAssignmentError(reason, i18n));
        }
      });
    return () => {
      active = false;
    };
  }, [accessToken, i18n, picked, slot.id]);

  function pick(person: AthleteOption | null) {
    setPicked(person);
    setOption(undefined);
    setPosition("end");
    setError(null);
  }

  const reasonText = (code: string | null | undefined) => {
    const key = placementReasonKey(code);
    return key ? i18n(key) : null;
  };
  const checking = picked !== null && option === undefined;
  const blocked = option?.blocked_reason ? reasonText(option.blocked_reason) : null;
  const waitlist = option?.waitlist === true && !blocked;
  const canSubmit = Boolean(picked && option && !blocked) && !saving;
  const matches = query.trim() ? addableMembers(people, slot) : [];

  async function submit() {
    if (!picked || !option || blocked) return;
    setSaving(true);
    setError(null);
    try {
      if (waitlist) await placeAdminUserOnWaitlist(accessToken, picked.id, { slot_id: slot.id, position });
      else await placeAdminUserInClass(accessToken, picked.id, { slot_id: slot.id, from_booking_id: null });
      onAdded();
      onClose();
    } catch (failure) {
      const key = placementReasonKey(failure instanceof ApiError ? failure.payload.code : null);
      setError(
        key && key !== "placementReasonOther"
          ? t("refused", { reason: i18n(key) })
          : localizeAdminAssignmentError(failure, i18n),
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      onClose={onClose}
      dismissible={!saving}
      eyebrow={slot.class_type.name}
      title={t("title")}
      size="md"
      variant="sheet"
      testId="add-to-class-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        void submit();
      }}
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose} disabled={saving}>
            {i18n("cancel77dfd21")}
          </DialogButton>
          <DialogButton tone="primary" type="submit" disabled={!canSubmit} testId="add-to-class-confirm">
            {saving ? t("saving") : waitlist ? t("waitlist") : t("book")}
          </DialogButton>
        </>
      }
    >
      {picked ? (
        <div className="space-y-4">
          <div
            className="flex min-h-11 items-center justify-between gap-3 rounded-2xl px-3 py-2"
            style={{ background: "var(--panel-muted)" }}
          >
            <span className="min-w-0 truncate text-sm font-semibold" style={{ color: "var(--text)" }} data-testid="add-to-class-person">
              {picked.nickname}
            </span>
            <button
              type="button"
              className="min-h-10 shrink-0 rounded-full px-3 text-xs font-bold"
              style={{ border: "1px solid var(--border-strong)", color: "var(--text)", background: "var(--panel)" }}
              onClick={() => pick(null)}
              disabled={saving}
            >
              {t("change")}
            </button>
          </div>
          {checking ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{t("checking")}</p>
          ) : option === null ? (
            error ? null : <p className="text-sm" style={{ color: "var(--dim)" }}>{t("unavailable")}</p>
          ) : blocked ? (
            <p className="text-sm" style={{ color: "var(--dim)" }} data-testid="add-to-class-blocked">
              {t("refused", { reason: blocked })}
            </p>
          ) : waitlist ? (
            <>
              <p className="text-sm" style={{ color: "var(--muted)" }}>{t("fullHint")}</p>
              <WaitlistPositionPicker
                name={`add-to-class-position-${slot.id}`}
                value={position}
                onChange={setPosition}
                endPlace={option?.waitlist_place}
                disabled={saving}
              />
            </>
          ) : (
            <p className="text-sm" style={{ color: "var(--muted)" }}>{t("bookHint")}</p>
          )}
        </div>
      ) : (
        <div>
          <label className="block text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {t("search")}
            <input
              type="search"
              autoFocus
              className="mt-2 min-h-11 w-full rounded-xl px-3 text-sm"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              data-testid="add-to-class-search"
            />
          </label>
          {matches.length ? (
            <ul className="mt-3 space-y-1.5">
              {matches.map((person) => (
                <li key={person.id}>
                  <button
                    type="button"
                    className="flex min-h-11 w-full items-center rounded-2xl px-3 text-start text-sm font-semibold"
                    style={{ background: "var(--panel-muted)", color: "var(--text)" }}
                    onClick={() => pick(person)}
                  >
                    {person.nickname}
                  </button>
                </li>
              ))}
            </ul>
          ) : query.trim() ? (
            <p className="mt-3 text-sm" style={{ color: "var(--dim)" }}>{t("noMatches")}</p>
          ) : null}
        </div>
      )}
      {error ? <ErrorNotice className="mt-3">{error}</ErrorNotice> : null}
    </Dialog>
  );
}
