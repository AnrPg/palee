# ADR-554: Εγώ is the profile others see
Date: 2026-11-08
Status: Accepted

## Context
ANR (2026-11-08) found that «Εγώ» read as a list of settings. ANR asked for a
page that feels like Instagram: a header with avatar, name and counts, a grid
of photos and videos first, then tabs for posts, PRs and badges. People add
tabs from their journal. «Εγώ» must look exactly like what others see; the
one difference is a section only the owner sees, where today's Εγώ rows go.

Before this, Εγώ (`MeHub` + `MeProfile`) and someone else's page
(`PersonPage`) were two different components, with different headers and tabs.

Mockups: `/mnt/project-files/milos/me-profile/me-profile-mockups-2026-11-08.html`.
ANR's picks: header **1A** (Instagram: avatar left, counts right), private
section **2A** (a ☰ button opening «Μόνο για σένα»), tabs **3C** (the owner
adds tabs from the profile with «+»). ANR's comments on the mockup: a shorter
list (language, profiles, sharing & visibility, connected devices and the
per-club notifications live in Ρυθμίσεις), tabs that always fit one row
(icon only when narrow), Instagram-style quiet buttons, and a header that
rearranges itself on small screens.

## Decision
1. **One profile component** (`PersonProfile`) serves `/me` and `/people/:id`.
   Εγώ is the owner's own profile plus the ☰ button (`MeSheet`).
2. **Profile card** (`community_profile_cards`, account-scoped): `bio`
   («Λίγα λόγια», up to 150 characters) and `tabs`, the optional tabs in the
   owner's order. Every signed-in session reads it (like a name); only the
   owner writes it (RLS). `PUT /api/me/profile-card`; `GET /api/people/:id`
   now returns `bio` and `tabs`.
3. **Tabs** (`Community.Domain.ProfileTabs`): «Πολυμέσα · Αναρτήσεις» always,
   first; optional «PRs» and «Διακρίσεις». Journal-private things (notes,
   wellbeing, body, injuries) are never offered.
4. **Who sees what inside a tab** is unchanged where it existed: posts and
   media by post audience (ADR-142, ADR-231), PRs by each PR's profile
   audience (ADR-196). Badges are new to others: the owner always, an active
   follower only while the owner shows «Διακρίσεις»
   (`user_achievements_profile_read_policy`, checked again in
   `SocialProfile.badges/2`). `GET /api/people/:id/badges`.
5. **«Μόνο για σένα»** keeps only what you *do*: Φέρε φίλο (when a box runs
   referrals), Φιλαράκι στήριξης, Πληρωμές & αποδείξεις, Ρυθμίσεις, Βοήθεια &
   ξενάγηση, Διαχείριση (staff) and Αποσύνδεση. Ρυθμίσεις gains rows for
   Κοινοποίηση & ορατότητα, Συνδεδεμένες συσκευές and Ειδοποιήσεις ανά box και
   club; language and profiles were already there.

## Rationale
One component removes the drift between the two pages and makes «what you
see is what they see» true by construction. The card is a separate table,
not `community_social_settings`, because those settings are owner-only while
the card is public display data.

## Alternatives Considered
- Tabs chosen per journal section (3A) or pinned per entry (3B): ANR picked
  adding them from the profile.
- A lock tab or an inline strip for the private section (2B, 2C): they make
  the owner's page differ from what others see.

## Consequences
- The «Clubs» tab of the old Εγώ is gone; the clubs list stays at
  `/me/clubs`, reached from Ρυθμίσεις.
- The rank line (ADR-400) stays for the owner under the header until a rank
  can be shown to others with its own audience.
- Follow-ups: «Προπονήσεις» and «Πρόοδος» tabs need a reader-scoped endpoint
  with their own audience; box and belt in the header need an owner choice
  to show them to others.

## Amends

- **ADR-545:** the language menu no longer sits on Εγώ. The app language is
  chosen only in Ρυθμίσεις (the «Γλώσσα εφαρμογής» picker already there).
