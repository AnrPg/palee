"use client";

import { AutomationsSettings } from "@/components/admin/automations/AutomationsSettings";

/**
 * «Αυτοματισμοί» in Στατιστικά & Μάρκετινγκ (W3 navigation decision): the
 * list of ready recipes with switches (W2 p3, ADR-346).
 */
export function AutomationsTab() {
  return (
    <div data-testid="automations-tab">
      <AutomationsSettings />
    </div>
  );
}
