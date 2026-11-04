"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { ApiError } from "@/api/client";
import { updateDraftWorkout } from "@/api/workouts";
import { backupFits, DraftSaver, type DraftBackup, type DraftBackupStore, type DraftSaveStatus } from "@/lib/draft-saver";

export function isStaleRevisionError(error: unknown) {
  return error instanceof ApiError && error.payload?.code === "stale_dsl_revision";
}

const BACKUP_PREFIX = "palee:draft-backup:";
/** A backup older than this is not recovered (the coach has long moved on). */
const BACKUP_MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000;

/**
 * Unsaved draft changes kept in this browser's local storage. Storage may be
 * missing or full (private mode, quota): then saving simply has no backup.
 */
export const localDraftBackupStore: DraftBackupStore = {
  read(key) {
    try {
      const raw = window.localStorage.getItem(BACKUP_PREFIX + key);
      if (!raw) return null;
      const backup = JSON.parse(raw) as Partial<DraftBackup>;
      if (!Array.isArray(backup.revisions) || typeof backup.savedAt !== "number" || !backup.payload) return null;
      if (Date.now() - backup.savedAt > BACKUP_MAX_AGE_MS) return null;
      return backup as DraftBackup;
    } catch {
      return null;
    }
  },
  write(key, backup) {
    try {
      window.localStorage.setItem(BACKUP_PREFIX + key, JSON.stringify(backup));
    } catch {
      // No room: the server save still runs.
    }
  },
  remove(key) {
    try {
      window.localStorage.removeItem(BACKUP_PREFIX + key);
    } catch {
      // Storage unavailable.
    }
  },
};

/**
 * Saves of editors that just went away, per draft. The editor that opens the
 * same draft next waits for them, so it loads what was just saved instead of
 * an older revision (whose first save would be refused as a conflict).
 */
const settling = new Map<string, Promise<void>>();

/** Waits for the last save of an editor of `draftId` that already closed. */
export function draftSettled(draftId: string | null | undefined): Promise<void> {
  return (draftId && settling.get(draftId)) || Promise.resolve();
}

type SendDraft = (token: string, draftId: string, payload: unknown) => Promise<{ dsl_source_revision?: number | null }>;

/**
 * One serialized draft saver per workout editor (see `DraftSaver`).
 *
 * Nothing the coach does is lost by accident:
 * - an editor that goes away (another tab, another page, the dialog closed)
 *   sends what was still waiting instead of dropping it;
 * - when the page is hidden (tab switched, app sent to the background, tab
 *   closed) what is waiting is sent at once;
 * - every change the server has not accepted yet is kept in this browser
 *   with the revision it is based on, and `loadDraft` saves it when the draft
 *   opens again on that same revision (a closed tab, a crash, no network).
 */
export function useDraftSaver<P extends object>({
  accessToken,
  draftId,
  onSaved,
  backup = localDraftBackupStore,
  send = updateDraftWorkout,
}: {
  accessToken: string | undefined;
  draftId: string | null;
  onSaved?: (revision: number) => void;
  backup?: DraftBackupStore | null;
  send?: SendDraft;
}) {
  const [status, setStatus] = useState<DraftSaveStatus>("idle");
  const [saver] = useState(
    () => new DraftSaver<P>({ isConflict: isStaleRevisionError, onStatus: setStatus, backup: backup ?? undefined }),
  );
  const latest = useRef({ accessToken, draftId, backup, send });

  // Declared before the editor's own effects, so saves always use the
  // current sign-in token and draft.
  useEffect(() => {
    latest.current = { accessToken, draftId, backup, send };
    saver.setTarget({
      send: (payload) =>
        accessToken && draftId
          ? send(accessToken, draftId, payload)
          : Promise.reject(new Error("The draft is not ready.")),
      onSaved,
      backupKey: draftId,
    });
  });

  useEffect(() => {
    saver.reopen();
    return () => {
      const id = latest.current.draftId;
      const done = saver.retire();
      if (!id) return;
      const tracked = done.finally(() => {
        if (settling.get(id) === tracked) settling.delete(id);
      });
      settling.set(id, tracked);
    };
  }, [saver]);

  // The page is being hidden or closed: send what is waiting now.
  useEffect(() => {
    const flush = () => {
      if (saver.started && saver.hasUnsaved && !saver.hasConflict) void saver.flush().catch(() => undefined);
    };
    const onVisibility = () => {
      if (document.visibilityState === "hidden") flush();
    };
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("pagehide", flush);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("pagehide", flush);
    };
  }, [saver]);

  /**
   * Loads the draft for the editor: after any save of an editor that just
   * closed, and with the changes this browser still holds for it saved
   * first, so the editor opens on everything the coach did. `revisionOf`
   * reads the draft revision from what `fetchDraft` returns.
   */
  const loadDraft = useCallback(
    async <T>(fetchDraft: () => Promise<T>, revisionOf: (loaded: T) => number | null | undefined): Promise<T> => {
      const { draftId: id } = latest.current;
      await draftSettled(id);
      const loaded = await fetchDraft();
      const { accessToken: token, backup: store, send: sendDraft } = latest.current;
      if (!id || !token || !store) return loaded;
      const kept = store.read(id);
      if (!kept) return loaded;
      const revision = revisionOf(loaded) ?? 0;
      if (!backupFits(kept, revision)) {
        // The draft was saved after this backup (here or elsewhere): it is out of date.
        store.remove(id);
        return loaded;
      }
      try {
        await sendDraft(token, id, { ...(kept.payload as object), expected_source_revision: revision });
        store.remove(id);
        return await fetchDraft();
      } catch {
        // Kept for the next try; the editor shows what the server has.
        return loaded;
      }
    },
    [],
  );

  return { saver, status, loadDraft };
}
