"use client";

import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";

import {
  deleteNotifications,
  fetchNotifications,
  type NotificationCategory,
  type NotificationFilter,
  type NotificationRecord,
} from "@/api/notifications";
import { useNotificationText } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { clockFormat } from "@/lib/clock";
import { useUiLocale } from "@/i18n/use-ui-locale";

const PAGE_SIZE = 20;
/** «Παλαιότερες από 30 μέρες». */
export const OLD_AFTER_DAYS = 30;

type StateChip = "all" | "read" | "old";

/** The filter the server applies to the list and to "select all". */
export function cleanupFilter(state: StateChip, category: NotificationCategory | null): NotificationFilter {
  return {
    ...(state === "read" ? { state: "read" as const } : {}),
    ...(state === "old" ? { older_than_days: OLD_AFTER_DAYS } : {}),
    ...(category ? { category } : {}),
  };
}

/**
 * «Εγώ › Ρυθμίσεις › Ειδοποιήσεις › Διαγραφή ειδοποιήσεων» (ADR-460): the
 * person's notifications, a page at a time, with a filter. «Επιλογή όλων (N)»
 * sends the filter itself, never ids, so it deletes exactly what matches.
 * Not undoable, so the button asks first.
 */
export function NotificationCleanup({ categories }: { categories: NotificationCategory[] }) {
  const t = useTranslations("NotificationActions");
  const tSettings = useTranslations("NotificationSettings");
  const uiLocale = useUiLocale();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const text = useNotificationText();

  const [state, setState] = useState<StateChip>("all");
  const [category, setCategory] = useState<NotificationCategory | null>(null);
  const [selected, setSelected] = useState<Set<string>>(() => new Set());
  const [allMatching, setAllMatching] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [deletedCount, setDeletedCount] = useState<number | null>(null);

  const filter = useMemo(() => cleanupFilter(state, category), [state, category]);

  // The card sits at the end of Settings' notifications section: its list is
  // read once the card comes near the screen, not on every Settings visit
  // (the inbox is otherwise read only when the bell opens).
  const sectionRef = useRef<HTMLElement | null>(null);
  const [nearScreen, setNearScreen] = useState(false);
  useEffect(() => {
    const element = sectionRef.current;
    if (!element) return;
    if (typeof IntersectionObserver === "undefined") {
      queueMicrotask(() => setNearScreen(true));
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setNearScreen(true);
          observer.disconnect();
        }
      },
      { rootMargin: "200px 0px" },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const list = useInfiniteQuery({
    queryKey: ["notifications", currentUser?.id, "cleanup", filter],
    enabled: Boolean(token) && nearScreen,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) =>
      fetchNotifications(token!, { limit: PAGE_SIZE, cursor: pageParam, filter, includeCount: pageParam === null }),
    getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined,
  });

  const rows = list.data?.pages.flatMap((page) => page.notifications) ?? [];
  const matchingCount = list.data?.pages[0]?.matching_count ?? 0;
  const count = allMatching ? matchingCount : selected.size;

  function resetSelection() {
    setSelected(new Set());
    setAllMatching(false);
  }

  function changeFilter(nextState: StateChip, nextCategory: NotificationCategory | null) {
    setState(nextState);
    setCategory(nextCategory);
    setDeletedCount(null);
    resetSelection();
  }

  function toggle(notification: NotificationRecord) {
    setDeletedCount(null);
    // Unticking one row of "all" keeps the rest of what is loaded.
    const base = allMatching ? new Set(rows.map((row) => row.id)) : new Set(selected);
    if (base.has(notification.id)) base.delete(notification.id);
    else base.add(notification.id);
    setAllMatching(false);
    setSelected(base);
  }

  const remove = useMutation({
    mutationFn: () =>
      deleteNotifications(token!, allMatching ? { filter } : { ids: Array.from(selected) }),
    onSuccess: async (result) => {
      setConfirming(false);
      setDeletedCount(result.deleted_count);
      resetSelection();
      await queryClient.invalidateQueries({ queryKey: ["notifications", currentUser?.id] });
    },
  });

  const stateChips: { value: StateChip; label: string }[] = [
    { value: "all", label: t("filterAll") },
    { value: "read", label: t("filterRead") },
    { value: "old", label: t("filterOld", { days: OLD_AFTER_DAYS }) },
  ];

  return (
    <section
      ref={sectionRef}
      className="rounded-[1.2rem] p-4"
      style={{ border: "1px solid var(--border)", background: "var(--panel-muted)" }}
      aria-labelledby="notification-cleanup-title"
      data-testid="notification-cleanup"
    >
      <h3 id="notification-cleanup-title" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("cleanupTitle")}
      </h3>
      <p className="mt-1 text-xs leading-5" style={{ color: "var(--muted)" }}>{t("cleanupHint")}</p>

      <div className="mt-3 flex flex-wrap gap-2" role="radiogroup" aria-label={t("filterLabel")}>
        {stateChips.map((chip) => (
          <Chip key={chip.value} active={state === chip.value} onClick={() => changeFilter(chip.value, category)}>
            {chip.label}
          </Chip>
        ))}
      </div>
      <div className="mt-2 flex flex-wrap gap-2" role="radiogroup" aria-label={t("categoryLabel")}>
        <Chip active={category === null} onClick={() => changeFilter(state, null)}>
          {t("allCategories")}
        </Chip>
        {categories.map((id) => (
          <Chip key={id} active={category === id} onClick={() => changeFilter(state, id)}>
            <CategoryTitle id={id} />
          </Chip>
        ))}
      </div>

      {list.isPending ? (
        <p className="mt-4 text-sm" style={{ color: "var(--dim)" }}>{tSettings("loading")}</p>
      ) : list.isError ? (
        <p className="mt-4 text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("listError")}</p>
      ) : rows.length === 0 ? (
        <p className="mt-4 text-sm" style={{ color: "var(--dim)" }}>{t("empty")}</p>
      ) : (
        <>
          <label className="mt-4 flex items-center gap-2 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            <input
              type="checkbox"
              checked={allMatching}
              onChange={(event) => {
                setDeletedCount(null);
                setSelected(new Set());
                setAllMatching(event.target.checked);
              }}
              data-testid="notification-cleanup-select-all"
            />
            {t("selectAll", { count: matchingCount })}
          </label>
          <ul className="mt-2 divide-y" style={{ borderColor: "var(--border)" }}>
            {rows.map((notification) => (
              <li key={notification.id} style={{ borderColor: "var(--border)" }}>
                <label className="flex cursor-pointer items-start gap-3 py-2.5">
                  <input
                    type="checkbox"
                    className="mt-1"
                    checked={allMatching || selected.has(notification.id)}
                    onChange={() => toggle(notification)}
                  />
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                      {text.title(notification)}
                    </span>
                    <span className="block text-xs" style={{ color: "var(--dim)" }}>
                      {clockFormat(uiLocale, { day: "numeric", month: "short", year: "numeric" }).format(
                        new Date(notification.inserted_at),
                      )}
                      {notification.read_at ? "" : ` · ${t("unread")}`}
                    </span>
                  </span>
                </label>
              </li>
            ))}
          </ul>
          {list.hasNextPage ? (
            <button
              type="button"
              className="mt-2 w-full rounded-full px-3 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              disabled={list.isFetchingNextPage}
              onClick={() => void list.fetchNextPage()}
            >
              {t("loadMore")}
            </button>
          ) : null}
        </>
      )}

      <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
        {deletedCount !== null ? (
          <p role="status" className="text-sm" style={{ color: "var(--muted)" }}>{t("deletedCount", { count: deletedCount })}</p>
        ) : (
          <span />
        )}
        <button
          type="button"
          className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
          style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
          disabled={count === 0 || remove.isPending}
          onClick={() => setConfirming(true)}
          data-testid="notification-cleanup-delete"
        >
          {t("deleteMany", { count })}
        </button>
      </div>

      {confirming ? (
        <Dialog
          onClose={() => setConfirming(false)}
          title={t("confirmTitle", { count })}
          size="sm"
          variant="center"
          dismissible={!remove.isPending}
          error={remove.isError ? t("deleteManyFailed") : undefined}
          footer={
            <div className="flex w-full justify-end gap-2">
              <button
                type="button"
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setConfirming(false)}
                disabled={remove.isPending}
              >
                {t("cancel")}
              </button>
              <button
                type="button"
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
                onClick={() => remove.mutate()}
                disabled={remove.isPending}
                data-testid="notification-cleanup-confirm"
              >
                {t("deleteMany", { count })}
              </button>
            </div>
          }
        >
          <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>{t("confirmBody")}</p>
        </Dialog>
      ) : null}
      {remove.isError && !confirming ? <ErrorNotice>{t("deleteManyFailed")}</ErrorNotice> : null}
    </section>
  );
}

function CategoryTitle({ id }: { id: NotificationCategory }) {
  const t = useTranslations("NotificationSettings");
  return <>{t(`category.${id}.title`)}</>;
}

function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={active}
      onClick={onClick}
      className="h-8 rounded-full px-3 text-xs font-semibold"
      style={
        active
          ? { background: "color-mix(in srgb, var(--primary) 16%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }
          : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }
      }
    >
      {children}
    </button>
  );
}
