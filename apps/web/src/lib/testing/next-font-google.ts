// Vitest stand-in for `next/font/google` (the real loader runs only in Next's
// compiler). Each font answers empty class names, so components render as is.
const font = (options?: object) => ({ className: "", variable: "", style: { fontFamily: "inherit" }, options });

export const Commissioner = font;
export const GFS_Didot = font;
export const Manrope = font;
export const Noto_Serif_Display = font;
export const Roboto_Flex = font;
export const Sofia_Sans_Extra_Condensed = font;
