# ADR-565: «Μοιράσου» after a WOD: a share card for Instagram, TikTok, Facebook, and on Palee
Date: 2026-11-09
Status: Accepted

## Context
ANR (2026-11-09): Strava grew because sharing was one tap away; Palee should make the post-WOD moment as smooth (one or two taps) and reach Instagram, Facebook and TikTok. Personal Instagram and Facebook accounts accept no posts from apps (Instagram's API is Business/Creator only and needs Meta review; Facebook dropped personal timelines in 2018; TikTok's direct post needs an audit and video). What works for everyone is the device's share sheet with an image, which is what Strava does today. Mockups: /mnt/project-files/milos/post-wod-share/post-wod-share-mockups-2026-11-09.html.

## Decision (ANR's picks, 10:41 UTC)
1. Alternative A: a share card on the WOD finish screen with «Μοιράσου» (share sheet) and «Και στο Palee», on by default, to the audience of the last post (the compose target).
2. Story (9:16) first, square on a tap; an optional photo behind the text.
3. The card shows the WOD, the score, exercises and loads, the box, the PR badge (PR cards), palee.app, the tagline, and the member's place on that day's box leaderboard (only when they show on leaderboards).
4. Auto-post: asked once, on the first finished WOD («Να ανεβαίνει αυτόματα κάθε WOD στο Palee;»); then the WOD posts itself with «Αναίρεση»; the switch lives in Κοινοποίηση & ορατότητα.
5. «Μοιράσου» also after a new PR, on a finished workout in the Journal, and on a finished challenge.
6. Connected accounts (true auto-post to Business/Creator accounts) are not built; they suit boxes' pages better and need Meta/TikTok review.

## Design
- API: `community_social_settings.auto_post_workouts` (nullable boolean, migration 20271109170000; null = never asked). `PUT /api/me/social/auto-post {enabled}`; `GET /api/me/social` carries `auto_post.enabled`. `SocialProfile.auto_post/2`, `set_auto_post/2`.
- Web, pure: `lib/share-card.ts` (layout helpers `exercisesLine`, `leaderboardPlace`, `wrapText`; `paintShareCard` draws with `SHARE_CARD_TOKENS` and `THEME_FONTS`; `shareCardFile` calls `navigator.share({files})` inside the tap and saves the image where files cannot be shared).
- Web, UI: `components/share-card/` (`ShareCardPanel`, `WodShare` with the one-time question and auto-post, `AutoPostSetting`, content builders in `subjects.tsx`, `uploadCardPhoto`). `community/publish-target.ts` holds the remembered target and publishing, shared with compose.
- The Palee post carries the journal attachment (WOD, PR). The card itself becomes the post's photo when there is no attachment (challenge) or the member added a photo.
- The auto-post's `client_operation_id` is `wod-auto-<execution id>`, so a reload never posts twice.
- The leaderboard place reuses `GET /org/:slug/community/wod-today?date=` for the day of the result.

## Consequences
- Android's in-app WebView has no Web Share API, so in the Android app the card is saved and the member posts it from Instagram. A native share plugin (@capacitor/share) is the follow-up; it needs an app release.
- WOD cards show no PR badge yet: a finished execution does not report the PRs it set.
