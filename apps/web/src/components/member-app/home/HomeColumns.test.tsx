import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { type HomeCard, HomeColumns } from "./HomeColumns";

const cards: HomeCard[] = [
  { key: "clubs", column: "feed", node: <p>clubs</p> },
  { key: "greeting", column: "reminders", node: <p>greeting</p> },
  { key: "wod", column: "feed", node: <p>wod</p> },
  { key: "empty", column: "reminders", node: null },
  { key: "events", column: "reminders", node: <p>events</p> },
  { key: "suggestions", column: "people", node: <p>suggestions</p> },
  { key: "posts", column: "feed", node: <p>posts</p> },
];

const texts = (root: ParentNode) => Array.from(root.querySelectorAll("p"), (p) => p.textContent);

describe("HomeColumns", () => {
  it("keeps the phone's one column in the given order", () => {
    const { container } = render(<HomeColumns cards={cards} layout="one" />);
    expect(container.querySelector("[data-home-columns]")).toBeNull();
    expect(texts(container)).toEqual(["clubs", "greeting", "wod", "events", "suggestions", "posts"]);
  });

  it("puts reminders left, the feed in the middle and people right, each in order", () => {
    const { container } = render(<HomeColumns cards={cards} layout="three" />);
    const column = (name: string) => container.querySelector(`[data-home-column="${name}"]`)!;
    expect(texts(column("reminders"))).toEqual(["greeting", "events"]);
    expect(texts(column("feed"))).toEqual(["clubs", "wod", "posts"]);
    expect(texts(column("people"))).toEqual(["suggestions"]);
    // DOM order is the reading order on screen: left, middle, right.
    expect(texts(container)).toEqual(["greeting", "events", "clubs", "wod", "posts", "suggestions"]);
  });

  it("keeps the reminders above the feed and puts people right in two columns", () => {
    const { container } = render(<HomeColumns cards={cards} layout="two" />);
    expect(container.querySelector('[data-home-column="reminders"]')).toBeNull();
    expect(texts(container.querySelector('[data-home-column="feed"]')!)).toEqual(["clubs", "greeting", "wod", "events", "posts"]);
    expect(texts(container.querySelector('[data-home-column="people"]')!)).toEqual(["suggestions"]);
  });

  it("keeps the side columns in view while the feed scrolls", () => {
    const { container } = render(<HomeColumns cards={cards} layout="three" />);
    for (const name of ["reminders", "people"]) {
      const side = container.querySelector(`[data-home-column="${name}"]`)!;
      expect(side.className).toContain("sticky");
      expect((side as HTMLElement).style.overflowY).toBe("auto");
    }
  });
});
