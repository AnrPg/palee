/**
 * The caret's position inside a textarea, relative to the textarea's own
 * box (scroll taken into account), measured with a hidden mirror element
 * that copies the textarea's text layout.
 */
const COPIED = [
  "boxSizing",
  "width",
  "borderTopWidth",
  "borderRightWidth",
  "borderBottomWidth",
  "borderLeftWidth",
  "paddingTop",
  "paddingRight",
  "paddingBottom",
  "paddingLeft",
  "fontStyle",
  "fontVariant",
  "fontWeight",
  "fontStretch",
  "fontSize",
  "lineHeight",
  "fontFamily",
  "textAlign",
  "textTransform",
  "textIndent",
  "letterSpacing",
  "wordSpacing",
  "tabSize",
] as const;

export function caretCoordinates(textarea: HTMLTextAreaElement, position: number): { top: number; left: number; height: number } {
  const doc = textarea.ownerDocument;
  const style = doc.defaultView?.getComputedStyle(textarea);
  const mirror = doc.createElement("div");
  const mirrorStyle = mirror.style as unknown as Record<string, string>;
  if (style) for (const key of COPIED) mirrorStyle[key] = (style as unknown as Record<string, string>)[key] ?? "";
  mirror.style.position = "absolute";
  mirror.style.visibility = "hidden";
  mirror.style.whiteSpace = "pre-wrap";
  mirror.style.overflowWrap = "break-word";
  mirror.style.top = "0";
  mirror.style.left = "-9999px";
  mirror.textContent = textarea.value.slice(0, position);
  const marker = doc.createElement("span");
  marker.textContent = textarea.value.slice(position) || ".";
  mirror.appendChild(marker);
  doc.body.appendChild(mirror);
  const lineHeight = Number.parseFloat(style?.lineHeight ?? "") || Number.parseFloat(style?.fontSize ?? "") * 1.3 || 18;
  const coords = {
    top: marker.offsetTop - textarea.scrollTop,
    left: marker.offsetLeft - textarea.scrollLeft,
    height: lineHeight,
  };
  doc.body.removeChild(mirror);
  return coords;
}
