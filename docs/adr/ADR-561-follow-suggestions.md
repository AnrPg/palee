# ADR-561: «Ίσως γνωρίζεις», a recommendation engine for people to follow
Date: 2026-11-09
Status: Accepted

## Context
ANR (2026-11-09): Palee's selling point is social bonding, so new people must find their crowd fast. Suggestions should be broad and loose for new people, and get personal once there is signal for them. Mockups with three placements: /mnt/project-files/milos/follow-suggestions/follow-suggestions-mockups-2026-11-09.html.

## Decision (ANR's picks)
1. Main surface: a row of cards «Ίσως γνωρίζεις» on the Αρχική, right above the posts, hidden when empty. Also: the full list in «+ Βρες» while its field is empty, and «Και αυτοί ίσως» on a profile right after following it (seeded with the people that profile follows).
2. Signals: follows you, same box, coach (or owner) of your box, common follows, same open club, same disciplines, same home area, recently active (ordering only, never shown), popular, new on Palee or in the box.
3. One reason under each name, naming up to two common follows.
4. Private accounts only with a real relation (follows you, shared box or open club, a common follow).
5. ✕ hides a person until they start following you; «Αναίρεση» undoes it.
6. Opting out of being suggested is the existing «Εμφάνιση στην αναζήτηση» switch, renamed «… και στις προτάσεις».
7. Broad to personal: gradual, by the viewer's own network (no cut-off).
8. Learning: anonymous daily counters per shown reason (shown, followed, dismissed).
9. The Αρχική card hides with ⋯ «Κρύψε τις προτάσεις» and comes back from Κοινοποίηση & ορατότητα.
10. «Ακολούθησε όλους» only on a first-run screen, which was not picked, so it is not built.

## Design (hexagonal)
- Infrastructure: migration 20271109150000. `palee_follow_suggestion_candidates(seed, pool, since)` (SECURITY DEFINER, bound to `app.user_id`) unions bounded sources (follows me, my boxes, people my follows follow, my open clubs, my home area, my disciplines, the seed's follows, the most followed, the recently active), applies every exclusion (me, existing follows or requests, blocks either way, demo people, unsearchable, dismissed unless followed me since, private without relation, box facts dropped for people hidden from member lists) and returns facts only. `palee_follow_suggestion_viewer()` gives the viewer's evidence. `community_follow_suggestion_dismissals` (owner RLS) and `community_follow_suggestion_events` (no person ids; written only by `palee_follow_suggestion_count`, read via `palee_follow_suggestion_rates`). `community_social_settings.show_follow_suggestions`.
- Port `Community.Ports.FollowSuggestionStore`, facade `Community.FollowSuggestionStore` (RepoContext), adapter `Infrastructure.Community.EctoFollowSuggestionStore`, public API `Community.FollowSuggestions`.
- Domain `Community.Domain.FollowSuggestionPolicy` (pure, deterministic): signals valued 0..1; weight = broad + (personal − broad) × maturity, maturity = evidence / (evidence + 10) with evidence = follows + 2·Buddies + open clubs + boxes; learned factor per reason = smoothed rate (prior 200 impressions at the overall rate, nothing learned before 500 shows) over the overall rate, bounded 0.5..2; variety: the n-th suggestion with the same reason keeps 0.85^(n−1) of its score; the shown reason is the explainable signal that contributed most. All tuning in one module.
- Application `Application.FollowSuggestions`: list (counts `shown`), follow (via `Follows.follow`, counts `followed`), dismiss/undismiss (counts `dismissed`).
- API: `GET /api/me/follow-suggestions?limit&seed`, `POST /api/me/follow-suggestions/:id/follow|dismiss {reason}`, `DELETE /api/me/follow-suggestions/:id/dismiss`; `PUT /api/me/social/privacy` takes `show_follow_suggestions`.
- Web: `components/social/FollowSuggestions.tsx` (Home row, Find list, after-follow row), `follow-suggestions-model.ts` (reason line), `FollowButton` `onFollow`, a third switch in AccountPrivacy. Query key outside `SOCIAL_KEY`, so following from a card does not pull it away.

## Consequences
- No ML or external service; everything runs in Postgres with indexes (new GIN on `account_interests.disciplines`, btree on `community_follows(user_id, target_type, status)`).
- The «most followed» source aggregates all user follows per request; when Palee grows, replace it with a periodically refreshed counter without touching the policy or UI.
- Never shown: training times or activity, distances, or the viewer's evidence.
