import { redirect } from "next/navigation";

// Automations live in the «Αυτοματισμοί» tab of Στατιστικά & Μάρκετινγκ.
export default function AdminAutomationsPage() {
  redirect("/admin/metrics?tab=automations");
}
