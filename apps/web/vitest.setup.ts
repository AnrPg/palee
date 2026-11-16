import "@testing-library/jest-dom/vitest";

// jsdom lays nothing out, so it has no scrolling: its window.scrollBy only logs
// "Not implemented: Window's scrollBy() method". Editors (ProseMirror scrolls the caret into
// view) call it on every change; a no-op keeps test output free of that noise.
if (typeof window !== "undefined") {
  window.scrollBy = () => undefined;
}
