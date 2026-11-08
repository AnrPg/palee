/**
 * The size a recharts ResponsiveContainer assumes before it measures its box.
 * Its own default (-1 × -1) logs "width(-1) and height(-1) of chart should be
 * greater than 0" on the first render; a positive size draws nothing visible
 * and is replaced by the measured one at once.
 */
export const CHART_FIRST_SIZE = { width: 1, height: 1 } as const;
