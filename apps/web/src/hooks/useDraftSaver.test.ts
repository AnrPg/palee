import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { DraftBackup, DraftBackupStore } from "@/lib/draft-saver";

import { draftSettled, localDraftBackupStore, useDraftSaver } from "./useDraftSaver";

type Payload = { title: string };

function memoryBackup(initial?: Record<string, DraftBackup>) {
  const entries = new Map<string, DraftBackup>(Object.entries(initial ?? {}));
  const store: DraftBackupStore = {
    read: (key) => entries.get(key) ?? null,
    write: (key, backup) => void entries.set(key, structuredClone(backup)),
    remove: (key) => void entries.delete(key),
  };
  return { entries, store };
}

/** A stand-in for the API that keeps one draft and its revision. */
function fakeDraftApi(revision: number, title = "server") {
  const draft = { title, dsl_source_revision: revision };
  const send = vi.fn(async (_token: string, _id: string, payload: unknown) => {
    const { expected_source_revision: expected, ...rest } = payload as Payload & { expected_source_revision: number };
    if (expected !== draft.dsl_source_revision) throw new Error("stale");
    draft.title = rest.title;
    draft.dsl_source_revision += 1;
    return { dsl_source_revision: draft.dsl_source_revision };
  });
  const fetchDraft = vi.fn(async () => ({ ...draft }));
  return { draft, send, fetchDraft };
}

describe("useDraftSaver", () => {
  afterEach(() => {
    vi.useRealTimers();
    window.localStorage.clear();
  });

  it("saves the changes this browser still holds before the editor opens", async () => {
    const api = fakeDraftApi(5);
    const { entries, store } = memoryBackup({ d1: { revisions: [5], payload: { title: "typed before the tab closed" }, savedAt: Date.now() } });
    const { result } = renderHook(() =>
      useDraftSaver<Payload>({ accessToken: "t", draftId: "d1", backup: store, send: api.send }),
    );
    const loaded = await result.current.loadDraft(api.fetchDraft, (draft) => draft.dsl_source_revision);
    expect(api.send).toHaveBeenCalledWith("t", "d1", { title: "typed before the tab closed", expected_source_revision: 5 });
    expect(loaded).toEqual({ title: "typed before the tab closed", dsl_source_revision: 6 });
    expect(entries.has("d1")).toBe(false);
  });

  it("drops a backup the draft has moved past", async () => {
    const api = fakeDraftApi(7);
    const { entries, store } = memoryBackup({ d1: { revisions: [5], payload: { title: "old" }, savedAt: Date.now() } });
    const { result } = renderHook(() =>
      useDraftSaver<Payload>({ accessToken: "t", draftId: "d1", backup: store, send: api.send }),
    );
    const loaded = await result.current.loadDraft(api.fetchDraft, (draft) => draft.dsl_source_revision);
    expect(api.send).not.toHaveBeenCalled();
    expect(loaded.title).toBe("server");
    expect(entries.has("d1")).toBe(false);
  });

  it("sends the waiting change when the editor goes away, and the next editor loads it", async () => {
    vi.useFakeTimers();
    const api = fakeDraftApi(3);
    const { store } = memoryBackup();
    const first = renderHook(() => useDraftSaver<Payload>({ accessToken: "t", draftId: "d1", backup: store, send: api.send }));
    act(() => {
      first.result.current.saver.start(3);
      first.result.current.saver.schedule({ title: "AMRAP 12" });
    });
    // The coach leaves before the autosave delay.
    first.unmount();
    await draftSettled("d1");
    expect(api.draft).toEqual({ title: "AMRAP 12", dsl_source_revision: 4 });

    const second = renderHook(() => useDraftSaver<Payload>({ accessToken: "t", draftId: "d1", backup: store, send: api.send }));
    const loaded = await second.result.current.loadDraft(api.fetchDraft, (draft) => draft.dsl_source_revision);
    expect(loaded).toEqual({ title: "AMRAP 12", dsl_source_revision: 4 });
  });

  it("sends the waiting change at once when the page is hidden", async () => {
    vi.useFakeTimers();
    const api = fakeDraftApi(3);
    const { result } = renderHook(() => useDraftSaver<Payload>({ accessToken: "t", draftId: "d1", backup: null, send: api.send }));
    act(() => {
      result.current.saver.start(3);
      result.current.saver.schedule({ title: "EMOM 10" });
    });
    await act(async () => {
      window.dispatchEvent(new Event("pagehide"));
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(api.send).toHaveBeenCalledTimes(1);
    expect(api.draft.title).toBe("EMOM 10");
  });

  it("keeps backups in local storage and forgets stale or broken ones", () => {
    localDraftBackupStore.write("d1", { revisions: [2], payload: { title: "x" }, savedAt: Date.now() });
    expect(localDraftBackupStore.read("d1")).toMatchObject({ revisions: [2], payload: { title: "x" } });
    localDraftBackupStore.write("d2", { revisions: [2], payload: { title: "x" }, savedAt: 0 });
    expect(localDraftBackupStore.read("d2")).toBeNull();
    window.localStorage.setItem("palee:draft-backup:d3", "{not json");
    expect(localDraftBackupStore.read("d3")).toBeNull();
    localDraftBackupStore.remove("d1");
    expect(localDraftBackupStore.read("d1")).toBeNull();
  });
});
