import { describe, expect, it } from "vitest";

import { greetingSentences } from "./GreetingCard";

describe("greetingSentences", () => {
  it("breaks after . ! ? … when a capital letter follows, with or without a space", () => {
    expect(greetingSentences("Καλημέρα!Πάμε δυνατά.Σήμερα PR")).toEqual(["Καλημέρα!", "Πάμε δυνατά.", "Σήμερα PR"]);
    expect(greetingSentences("Hey pal. Ready?Go… Now")).toEqual(["Hey pal.", "Ready?", "Go…", "Now"]);
  });

  it("keeps a sentence whole when no capital follows the stop", () => {
    expect(greetingSentences("3.5 km today, nice")).toEqual(["3.5 km today, nice"]);
    expect(greetingSentences("Wow?! Next")).toEqual(["Wow?!", "Next"]);
    expect(greetingSentences("")).toEqual([]);
  });
});
