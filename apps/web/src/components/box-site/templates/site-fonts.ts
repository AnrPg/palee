import { Commissioner, GFS_Didot, Manrope, Noto_Serif_Display, Roboto_Flex, Sofia_Sans_Extra_Condensed } from "next/font/google";

/**
 * ADR-530: the templates' typefaces, self-hosted by next/font, with Greek.
 * Only the website imports this module, so the app never loads them. Nothing
 * is preloaded: a page uses the two faces of its template only, and the
 * browser fetches just those.
 */
const commissioner = Commissioner({ subsets: ["latin", "greek"], variable: "--bw-commissioner", display: "swap", preload: false });
const sofia = Sofia_Sans_Extra_Condensed({ subsets: ["latin", "greek"], weight: ["800", "900"], style: ["normal", "italic"], variable: "--bw-sofia", display: "swap", preload: false });
const manrope = Manrope({ subsets: ["latin", "greek"], variable: "--bw-manrope", display: "swap", preload: false });
const robotoFlex = Roboto_Flex({ subsets: ["latin", "greek"], variable: "--bw-roboto-flex", display: "swap", preload: false });
const didot = GFS_Didot({ subsets: ["latin", "greek"], weight: "400", variable: "--bw-didot", display: "swap", preload: false });
const notoSerif = Noto_Serif_Display({ subsets: ["latin", "greek"], style: ["italic"], weight: ["300", "400"], variable: "--bw-noto-serif", display: "swap", preload: false });

/** The class that defines the `--bw-*` font variables the templates' CSS reads. */
export const siteFontClass = [commissioner, sofia, manrope, robotoFlex, didot, notoSerif].map((font) => font.variable).join(" ");
