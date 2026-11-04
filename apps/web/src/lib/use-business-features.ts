"use client";

import { useMemo } from "react";
import { useQueries, useQuery } from "@tanstack/react-query";

import { businessFeaturesKey, fetchBusinessFeatures, type BusinessFeature } from "@/api/business-features";
import { useSession } from "@/components/session-provider";
import { featureOn, showsWork, type BusinessFeatureState } from "@/lib/business-features";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";

export type BusinessFeatures = {
  state: BusinessFeatureState;
  /** Whether `key` is on for this business (see `featureOn`). */
  on: (key: BusinessFeature) => boolean;
  /** Whether a work list tied to `key` with `pending` rows is shown (see `showsWork`). */
  shows: (key: BusinessFeature, pending: number | null | undefined) => boolean;
};

function wrap(state: BusinessFeatureState): BusinessFeatures {
  return {
    state,
    on: (key) => featureOn(state, key),
    shows: (key, pending) => showsWork(state, key, pending),
  };
}

/**
 * ADR-470: which optional features the current business (or `slug`) has on.
 * `locationIds` is the page's branch filter, for features a branch can have
 * on its own (promotions, a floor plan). One cached read per business and filter.
 */
export function useBusinessFeatures(options: { slug?: string | null; locationIds?: string | null } = {}): BusinessFeatures {
  const currentSlug = useOrganizationSlug();
  const slug = options.slug ?? currentSlug;
  const token = useSession().tokens?.access_token ?? null;

  const query = useQuery({
    queryKey: businessFeaturesKey(slug ?? "", options.locationIds),
    enabled: Boolean(token && slug),
    queryFn: () => fetchBusinessFeatures(token!, slug!, options.locationIds),
    staleTime: FRESHNESS.reference,
  });

  return useMemo(
    () =>
      wrap(
        query.isError
          ? { status: "error" }
          : query.data
            ? { status: "ready", features: query.data }
            : { status: "loading" },
      ),
    [query.isError, query.data],
  );
}

/** Whether `key` is on at any of `slugs` (e.g. any box the member belongs to). */
export function useFeatureAtAnyBusiness(slugs: string[], key: BusinessFeature): boolean {
  const token = useSession().tokens?.access_token ?? null;
  const results = useQueries({
    queries: slugs.map((slug) => ({
      queryKey: businessFeaturesKey(slug),
      enabled: Boolean(token),
      queryFn: () => fetchBusinessFeatures(token!, slug),
      staleTime: FRESHNESS.reference,
    })),
  });
  return results.some((result) =>
    featureOn(result.isError ? { status: "error" } : result.data ? { status: "ready", features: result.data } : { status: "loading" }, key),
  );
}
