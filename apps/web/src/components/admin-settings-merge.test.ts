import { describe, expect, it } from "vitest";

import { mergeServerForm } from "./admin-settings";

type Form = { shields: string; leaderboard: boolean; timeout: number | null };
const form: Form = { shields: "1", leaderboard: true, timeout: 60 };

describe("mergeServerForm", () => {
  it("takes every server value on the first answer", () => {
    expect(mergeServerForm(form, null, { shields: "3", leaderboard: false, timeout: null })).toEqual({
      shields: "3",
      leaderboard: false,
      timeout: null,
    });
  });

  it("keeps the form's value for a field the server left out, so no input turns uncontrolled", () => {
    const merged = mergeServerForm(form, null, { shields: "2", leaderboard: undefined });
    expect(merged).toEqual({ shields: "2", leaderboard: true, timeout: 60 });
  });

  it("keeps what was typed here and not saved yet", () => {
    const lastServer = { shields: "1", leaderboard: true, timeout: 60 };
    const typed = { ...form, shields: "5" };
    expect(mergeServerForm(typed, lastServer, { shields: "2", leaderboard: false, timeout: 30 })).toEqual({
      shields: "5",
      leaderboard: false,
      timeout: 30,
    });
  });

  it("takes a field the server sends for the first time", () => {
    expect(mergeServerForm(form, { shields: "1" }, { shields: "1", leaderboard: false })).toEqual({
      shields: "1",
      leaderboard: false,
      timeout: 60,
    });
  });
});
