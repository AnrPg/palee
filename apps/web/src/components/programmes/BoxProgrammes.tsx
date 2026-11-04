"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchBoxProgrammes } from "@/api/programmes";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { FRESHNESS } from "@/lib/query-policy";

import { ProgrammeTile } from "./ProgrammeTile";

/**
 * Every programme a box sells, reached from «Όλα τα προγράμματα (N)» on its
 * website (ADR-543): the same cards as the website, in a grid.
 */
export function BoxProgrammes({ slug }: { slug: string }) {
  const t = useTranslations("Programmes");
  const query = useQuery({ queryKey: ["public", "box-programmes", slug], queryFn: () => fetchBoxProgrammes(slug), staleTime: FRESHNESS.reference });
  const boxName = typeof query.data?.box?.name === "string" ? query.data.box.name : slug;
  const list = (Array.isArray(query.data?.programmes) ? query.data.programmes : []).filter((entry) => entry && typeof entry.id === "string");
  const base = `/b/${encodeURIComponent(slug)}`;
  return (
    <main className="mx-auto flex w-full max-w-6xl flex-col gap-4 px-4 pb-10 pt-4 lg:px-6 lg:pt-6" data-testid="box-programmes">
      <BackLink href={base}>{boxName}</BackLink>
      <h1 className="text-2xl font-extrabold lg:text-3xl" style={{ color: "var(--text)" }}>{t("title")}</h1>
      {query.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {query.isError ? <ErrorNotice>{t("loadFailed")}</ErrorNotice> : null}
      {query.isSuccess && list.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("buyer2.boxEmpty")}</p> : null}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 lg:gap-4">
        {list.map((programme) => (
          <ProgrammeTile key={programme.id} programme={programme} href={`${base}/programmes/${encodeURIComponent(programme.id)}`} testId={`box-programme-${programme.id}`} />
        ))}
      </div>
    </main>
  );
}
