import "./site-fonts.css";

/**
 * ADR-530: the templates' typefaces, self-hosted with Greek (site-fonts.css,
 * files in ./fonts). Only the website imports this module, so the app never
 * loads them. Nothing is preloaded: a page uses the two faces of its template
 * only, and the browser fetches just those.
 */
export const siteFontClass = "bw-fonts";
