"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { CLASS_LEVELS, classLevelsOf, suitsLevels } from "@/api/schedule";
import { fetchBoxSchedule, type PublicBoxPage, type PublicBoxSchedule } from "@/api/social";
import { WeekStrip, weekStart } from "@/components/member-app/box/schedule/WeekStrip";
import { TrialSheet } from "@/components/trials/TrialSheet";
import type { TrialOffer } from "@/api/trials";
import { addDaysToKey, dateKeyInZone, formatInZone, startOfDayInZone, zonedText } from "@/lib/zoned-time";
import { YourTime } from "@/components/zoned-time";
import { CollapsibleFilterBar } from "@/components/filters/CollapsibleFilterBar";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useMediaQuery } from "@/lib/use-media-query";

type Slot = PublicBoxSchedule["slots"][number];
const ALL = "";

/**
 * Πρόγραμμα for visitors (plan §5a board 4 Q7): the members' week strip and
 * compact rows with a chip row for class type, level and audience, and a
 * class sheet without booking or package dimming. Members of the gym get a
 * link to their own Πρόγραμμα, where they book. Classes that take trial
 * guests carry a «Δοκιμαστικό» tag and a chip filter, and their sheet opens
 * the trial sheet with the class picked (board 6 Q2). Desktop (ADR-621, ANR
 * 2026-11-10 S1): the whole week in seven columns, with the week's arrows,
 * «Σήμερα» and the filter chips in one row above it.
 */
export function VisitorSchedule({ page, token, member }: { page: PublicBoxPage; token: string; member: boolean }) {
  const t = useTranslations("BoxPage");
  const tSchedule = useTranslations("BoxSchedule");
  const tTrials = useTranslations("Trials");
  const locale = useLocale();
  // ADR-179: the gym's days and clock, wherever the visitor is.
  const zone = (page as { time_zone?: string | null }).time_zone ?? null;
  const [selectedDate, setSelectedDate] = useState(() => dateKeyInZone(new Date(), zone));
  const [type, setType] = useState(ALL);
  const [level, setLevel] = useState(ALL);
  const [audience, setAudience] = useState(ALL);
  const [open, setOpen] = useState<Slot | null>(null);
  const [trialOnly, setTrialOnly] = useState(false);
  const [trialSlot, setTrialSlot] = useState<Slot | null>(null);
  const monday = weekStart(selectedDate);

  const schedule = useQuery({
    queryKey: ["social", "box-schedule", page.box.slug, monday, zone],
    queryFn: () =>
      fetchBoxSchedule(token, page.box.slug, {
        startAt: startOfDayInZone(monday, zone).toISOString(),
        endAt: startOfDayInZone(addDaysToKey(monday, 7), zone).toISOString(),
      }),
  });

  const slots = useMemo(() => schedule.data?.slots ?? [], [schedule.data]);
  const offer = (schedule.data?.trial_offer ?? null) as TrialOffer | null;
  const canAsk = Boolean(offer && !offer.blocked_reason && !offer.mine);
  const takesTrials = (slot: Slot) => canAsk && (slot.trial_seats ?? 0) > 0;
  const types = useMemo(
    () => [...new Map(slots.filter((slot) => slot.class_type).map((slot) => [slot.class_type!.id, slot.class_type!.name])).entries()],
    [slots],
  );
  const audiences = useMemo(() => [...new Set(slots.flatMap((slot) => slot.class_type?.audiences ?? []))], [slots]);
  // ADR-490: a class type suits several levels; one with none suits all of them. Offer the
  // levels some class suits (same rule as the filter), and only when a class narrows them.
  const levels = slots.some((slot) => (slot.class_type?.levels?.length ?? 0) > 0)
    ? CLASS_LEVELS.filter((value) => slots.some((slot) => slot.class_type && suitsLevels(slot.class_type.levels, [value])))
    : [];
  const desktop = useMediaQuery("(min-width: 64rem)");
  const today = dateKeyInZone(new Date(), zone);
  const shown = slots
    .filter((slot) => !type || slot.class_type?.id === type)
    .filter((slot) => !level || suitsLevels(slot.class_type?.levels, [level]))
    .filter((slot) => !audience || (slot.class_type?.audiences ?? []).includes(audience))
    .filter((slot) => !trialOnly || takesTrials(slot))
    .sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at));
  const day = shown.filter((slot) => dateKeyInZone(slot.scheduled_at, zone) === selectedDate);
  const locationName = (id: string | null | undefined) =>
    page.locations.length > 1 ? (page.locations.find((location) => location.id === id)?.name ?? null) : null;

  function clearFilters() {
    setType(ALL);
    setLevel(ALL);
    setAudience(ALL);
    setTrialOnly(false);
  }
  const chips = (
    <div className="flex flex-wrap gap-2">
      <Chip label={tSchedule("chipType")} value={type} onChange={setType} options={types.map(([id, name]) => ({ value: id, label: name }))} />
      <Chip
        label={tSchedule("chipLevel")}
        value={level}
        onChange={setLevel}
        options={levels.map((value) => ({ value, label: tSchedule(`level_${value}`) }))}
      />
      <Chip
        label={tSchedule("audience")}
        value={audience}
        onChange={setAudience}
        options={audiences.map((value) => ({ value, label: audienceLabel(tSchedule, value) }))}
      />
      {canAsk && slots.some(takesTrials) ? (
        <button
          type="button"
          aria-pressed={trialOnly}
          onClick={() => setTrialOnly((value) => !value)}
          className="flex min-h-10 shrink-0 items-center rounded-full px-3.5 text-sm font-semibold"
          style={
            trialOnly
              ? { background: "var(--text)", color: "var(--bg)" }
              : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }
          }
        >
          {tTrials("chipTrial")}
        </button>
      ) : null}
    </div>
  );

  return (
    <div className="flex flex-col gap-3">
      {desktop ? (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <WeekNav monday={monday} today={today} onSelect={setSelectedDate} />
          {chips}
        </div>
      ) : (
        <>
          <WeekStrip selectedDate={selectedDate} today={today} onSelect={setSelectedDate} />
          <CollapsibleFilterBar
            ariaLabel={tSchedule("filtersAria")}
            activeCount={[type, level, audience].filter((value) => value !== ALL).length + (trialOnly ? 1 : 0)}
            onClear={clearFilters}
          >
            {chips}
          </CollapsibleFilterBar>
        </>
      )}

      {schedule.isPending ? <p className="py-6 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {schedule.isError ? (
        <ErrorNotice
          className="my-6"
          action={
            <button type="button" onClick={() => void schedule.refetch()} className="font-bold underline">
              {tSchedule("retry")}
            </button>
          }
        >
          {tSchedule("loadFailed")}
        </ErrorNotice>
      ) : null}
      {desktop && schedule.isSuccess ? (
        <WeekGrid monday={monday} today={today} zone={zone} slots={shown} locale={locale} trial={takesTrials} onOpen={setOpen} />
      ) : null}
      {!desktop && schedule.isSuccess && day.length === 0 ? (
        <p className="rounded-2xl p-5 text-center text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          {tSchedule("emptyDay")}
        </p>
      ) : null}
      <ul className="flex flex-col gap-2 lg:hidden">
        {(desktop ? [] : day).map((slot) => (
          <li key={slot.id}>
            <Row slot={slot} locale={locale} zone={zone} location={locationName(slot.location_id)} trial={takesTrials(slot)} onOpen={() => setOpen(slot)} />
          </li>
        ))}
      </ul>
      {open ? (
        <VisitorClassSheet
          slot={open}
          zone={zone}
          location={page.locations.find((location) => location.id === open.location_id)?.name ?? null}
          memberHref={member ? `/org/${page.box.slug}/box/schedule?open_slot=${open.id}` : null}
          onTrial={takesTrials(open) && new Date(open.scheduled_at) > new Date() ? () => (setTrialSlot(open), setOpen(null)) : null}
          onClose={() => setOpen(null)}
        />
      ) : null}
      {trialSlot && offer ? (
        <TrialSheet page={page} token={token} offer={offer} initialSlot={trialSlot} onClose={() => setTrialSlot(null)} />
      ) : null}
    </div>
  );
}

/** A calendar day ("YYYY-MM-DD") as a Date at its noon, for naming it in the visitor's language. */
const noonOf = (key: string) => new Date(`${key}T12:00:00`);

/** Desktop: ‹ 9 – 15 Νοεμβρίου › and «Σήμερα» (ADR-621). */
function WeekNav({ monday, today, onSelect }: { monday: string; today: string; onSelect: (key: string) => void }) {
  const t = useTranslations("BoxSchedule");
  const locale = useLocale();
  const range = new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" }).formatRange(noonOf(monday), noonOf(addDaysToKey(monday, 6)));
  const thisWeek = weekStart(today) === monday;
  const arrow = "grid h-10 w-10 place-items-center rounded-xl text-lg";
  const box = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };
  return (
    <nav aria-label={t("weekAria")} className="flex items-center gap-2">
      <button type="button" onClick={() => onSelect(addDaysToKey(monday, -7))} aria-label={t("previousWeek")} className={arrow} style={box}>
        <span aria-hidden="true" className="rtl:rotate-180">‹</span>
      </button>
      <b className="min-w-44 text-center text-base" style={{ color: "var(--text)" }} data-testid="schedule-week-range">{range}</b>
      <button type="button" onClick={() => onSelect(addDaysToKey(monday, 7))} aria-label={t("nextWeek")} className={arrow} style={box}>
        <span aria-hidden="true" className="rtl:rotate-180">›</span>
      </button>
      <button type="button" onClick={() => onSelect(today)} disabled={thisWeek} className="min-h-10 rounded-xl px-4 text-sm font-bold disabled:opacity-50" style={box}>
        {t("today")}
      </button>
    </nav>
  );
}

/**
 * Desktop (ADR-621 S1): the week in seven columns, each day's classes as
 * small tiles in time order. Past classes fade, a full one says so; a tile
 * opens the class sheet like a row does on phones.
 */
export function WeekGrid({
  monday,
  today,
  zone,
  slots,
  locale,
  trial,
  onOpen,
}: {
  monday: string;
  today: string;
  zone: string | null;
  slots: Slot[];
  locale: string;
  trial: (slot: Slot) => boolean;
  onOpen: (slot: Slot) => void;
}) {
  const t = useTranslations("BoxSchedule");
  const tTrials = useTranslations("Trials");
  const weekday = new Intl.DateTimeFormat(locale, { weekday: "short" });
  const now = new Date();
  const days = Array.from({ length: 7 }, (_, index) => addDaysToKey(monday, index));
  return (
    <div role="list" aria-label={t("weekGridAria")} className="grid grid-cols-7 gap-2.5" data-testid="schedule-week-grid">
      {days.map((key) => {
        const own = slots.filter((slot) => dateKeyInZone(slot.scheduled_at, zone) === key);
        const isToday = key === today;
        return (
          <div role="listitem" key={key} className="flex min-w-0 flex-col gap-2" aria-current={isToday ? "date" : undefined}>
            <div
              className="rounded-xl py-1.5 text-center text-xs font-bold"
              style={isToday ? { background: "var(--text)", color: "var(--bg)" } : { color: "var(--dim)" }}
            >
              <span className="first-letter:uppercase">{weekday.format(noonOf(key))}</span>
              <span className="block text-lg font-extrabold" style={isToday ? undefined : { color: "var(--text)" }}>
                {Number(key.slice(8, 10))}
              </span>
            </div>
            {own.length === 0 ? (
              <span aria-hidden="true" className="py-2 text-center text-sm" style={{ color: "var(--dim)" }}>
                –
              </span>
            ) : (
              own.map((slot) => {
                const past = new Date(slot.scheduled_at) < now;
                const full = slot.spots_remaining === 0;
                const status = past ? null : full ? t("statusFull") : slot.spots_remaining != null ? t("spotsLeft", { count: slot.spots_remaining }) : null;
                return (
                  <button
                    key={slot.id}
                    type="button"
                    onClick={() => onOpen(slot)}
                    className="flex min-w-0 flex-col items-start rounded-xl px-2.5 py-2 text-start text-xs leading-snug"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)", opacity: past ? 0.5 : 1 }}
                  >
                    <span className="text-sm font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{zonedText(slot.scheduled_at, zone, locale, "time")}</span>
                    <span className="w-full truncate font-bold" style={{ color: "var(--text)" }}>{slot.name}</span>
                    {slot.coach?.nickname ? <span className="w-full truncate" style={{ color: "var(--dim)" }}>{slot.coach.nickname}</span> : null}
                    {status ? <span className="font-bold" style={{ color: full ? "var(--danger, var(--dim))" : "var(--success)" }}>{status}</span> : null}
                    {trial(slot) && !past ? (
                      <span className="mt-1 rounded-full px-2 py-0.5 text-[11px] font-bold" style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" }}>
                        {tTrials("tag")}
                      </span>
                    ) : null}
                  </button>
                );
              })
            )}
          </div>
        );
      })}
    </div>
  );
}

function audienceLabel(t: ReturnType<typeof useTranslations<"BoxSchedule">>, value: string) {
  return t.has(`audience_${value}`) ? t(`audience_${value}` as never) : value;
}

function Chip({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (value: string) => void;
}) {
  const t = useTranslations("BoxSchedule");
  if (options.length === 0) return null;
  const active = value !== ALL;
  return (
    <label
      className="relative flex min-h-10 shrink-0 items-center rounded-full ps-3.5 pe-8 text-sm font-semibold"
      style={
        active
          ? { background: "var(--text)", color: "var(--bg)" }
          : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }
      }
    >
      <span>{active ? options.find((option) => option.value === value)?.label : label}</span>
      <span aria-hidden="true" className="pointer-events-none absolute end-3 text-xs">▾</span>
      <Select
        aria-label={label}
        value={value}
        onValueChange={(value) => onChange(value)}
        className="absolute inset-0 cursor-pointer opacity-0"
      >
        <option value={ALL}>{t("optionAll")}</option>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </Select>
    </label>
  );
}

function Row({
  slot,
  locale,
  zone,
  location,
  trial,
  onOpen,
}: {
  slot: Slot;
  locale: string;
  zone: string | null;
  location: string | null;
  trial: boolean;
  onOpen: () => void;
}) {
  const t = useTranslations("BoxSchedule");
  const tTrials = useTranslations("Trials");
  const time = zonedText(slot.scheduled_at, zone, locale, "time");
  const detail = [slot.coach?.nickname, location].filter(Boolean).join(" · ");
  const past = new Date(slot.scheduled_at) < new Date();
  return (
    <button
      type="button"
      onClick={onOpen}
      className="grid min-h-16 w-full grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl px-4 py-3 text-start"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", opacity: past ? 0.55 : 1 }}
    >
      <span className="flex flex-col items-start">
        <span className="font-mono text-sm font-bold" style={{ color: "var(--text-soft)" }}>{time}</span>
        {slot.duration_minutes ? (
          <span className="text-[11px]" style={{ color: "var(--dim)" }}>{t("minutes", { count: slot.duration_minutes })}</span>
        ) : null}
      </span>
      <span className="flex min-w-0 flex-col">
        <span className="flex min-w-0 items-center gap-2">
          <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{slot.name}</span>
          {trial && !past ? (
            <span className="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold" style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" }}>
              {tTrials("tag")}
            </span>
          ) : null}
        </span>
        {detail ? <span className="truncate text-xs" style={{ color: "var(--dim)" }}>{detail}</span> : null}
      </span>
      <span className="text-xs font-bold" style={{ color: past ? "var(--dim)" : slot.spots_remaining === 0 ? "var(--dim)" : "var(--success)" }}>
        {past ? t("statusPast") : slot.spots_remaining === 0 ? t("statusFull") : slot.spots_remaining != null ? t("spotsLeft", { count: slot.spots_remaining }) : null}
      </span>
    </button>
  );
}

function VisitorClassSheet({
  slot,
  zone,
  location,
  memberHref,
  onTrial,
  onClose,
}: {
  slot: Slot;
  zone: string | null;
  location: string | null;
  memberHref: string | null;
  onTrial: (() => void) | null;
  onClose: () => void;
}) {
  const t = useTranslations("BoxPage");
  const tTrials = useTranslations("Trials");
  const tSchedule = useTranslations("BoxSchedule");
  const locale = useLocale();
  const start = new Date(slot.scheduled_at);
  const when = formatInZone(start, zone, locale, { weekday: "long", day: "numeric", month: "long" });
  const clock = zonedText(start, zone, locale, "time");
  const levels = slot.class_type ? classLevelsOf(slot.class_type.levels) : null;
  const facts = [
    slot.coach?.nickname ? [tSchedule("coach"), slot.coach.nickname] : null,
    levels
      ? [
          tSchedule("chipLevel"),
          levels.length === 0 ? tSchedule("level_all_levels") : levels.map((value) => tSchedule(`level_${value}`)).join(", "),
        ]
      : null,
    slot.class_type && slot.class_type.audiences.length > 0
      ? [tSchedule("audience"), slot.class_type.audiences.map((value) => audienceLabel(tSchedule, value)).join(", ")]
      : null,
    location ? [tSchedule("location"), location] : null,
    slot.spots_remaining != null ? [t("spots"), slot.spots_remaining === 0 ? tSchedule("statusFull") : tSchedule("spotsLeft", { count: slot.spots_remaining })] : null,
  ].filter(Boolean) as [string, string][];

  return (
    <Dialog
      onClose={onClose}
      title={slot.name}
      titleId="visitor-class-title"
      description={
        <span className="block font-semibold first-letter:uppercase">
          {when} · {clock}
          <YourTime at={start} zone={zone} format="day-time" />
          {slot.duration_minutes ? ` · ${tSchedule("minutes", { count: slot.duration_minutes })}` : ""}
        </span>
      }
      closeLabel={t("close")}
      size="xl"
      footer={
        <div className="flex w-full flex-col gap-2">
          {memberHref ? (
            <Link href={memberHref} className="flex min-h-12 items-center justify-center rounded-2xl text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {t("bookAsMember")}
            </Link>
          ) : onTrial ? (
            <button type="button" onClick={onTrial} className="flex min-h-12 items-center justify-center rounded-2xl text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {tTrials("bookWithTrial")}
            </button>
          ) : null}
          <button type="button" onClick={onClose} className="min-h-11 rounded-2xl text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("close")}
          </button>
        </div>
      }
    >
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
            {facts.map(([term, value]) => (
              <div key={term} className="contents">
                <dt style={{ color: "var(--dim)" }}>{term}</dt>
                <dd style={{ color: "var(--text)" }}>{value}</dd>
              </div>
            ))}
          </dl>
    </Dialog>
  );
}
