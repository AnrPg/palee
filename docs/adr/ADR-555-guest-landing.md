# ADR-555: palee.app sells Palee to guests (the guest landing)
Date: 2026-11-08
Status: Accepted

## Context
ANR (2026-11-08) asked to split the signed-out page in two: one part keeps
the sign-in and sign-up form as it is, the other "sells" Palee with
animations, photos and standout boxes, responsive with a different approach
per screen size. Until now `/` sent guests to `/login`, which showed only the
form (`AuthConsole`).

ANR set the selling point: social bonding over training (sharing PRs and
photos, kudos, training partners) and the Journal as a psychological tool and
progress log, with many automations under the hood; booking and the box come
after. ANR also set the tagline, the same words in every locale:
«Hey pal, the real PR is coming back πάλι (palee)!» («πάλι» always Greek).

Mockups (alternatives A, B, B+, C, D and four form styles):
`/mnt/project-files/milos/landing/landing-mockups-2026-11-08.html`.
ANR picked **B+1**.

## Decision
- `GuestLanding` (`components/landing/`) is what guests see on `/`, `/login`
  and `/register`. `/` shows it with the form closed (`GuestHome` swaps it for
  the app once signed in); `/login` and `/register` open the form right away,
  so every existing link, `next` and `token` keeps working.
- Phones (< 640px): seven full-screen stories (hero with tagline and photo,
  sharing with your crew, Journal, PR progress with the drawn line, training
  partners, the box: class booking and independent coaches, automations).
  Progress bars, tap the start third to go back and the rest to go on, a
  pause button, hold ≥ 250 ms to pause and let go to resume without turning
  the page. «Create account» and «I already have an account» open the form in
  a bottom sheet.
- Tablets and up: a dark top bar (Sign in, Create account), a first screen
  that is all dark with the tagline, headline and lede on the start side and
  a phone that plays the app (Feed, Training partners, Journal, your week) on
  the end side, and a floating Spark «See more» that scrolls to the rest:
  four pillars, a marquee, «Why you'll open it every day» tiles and the card
  for box owners and coaches (→ business account). The form opens in an end
  drawer that is a Dojo-blue column with the card centred (form style 1).
- The form itself is `AuthPanel`, split out of `AuthConsole` unchanged. Its
  `onContinue` lets `/` keep the landing until the form is done, so a new
  account still sees its recovery codes first.
- While the form is open the landing is `inert` and `aria-hidden`.
- The tagline is `PaleeTagline`, never translated. Inside the app it shows on
  the loading screen (`AuthGuard`), once on the first step after sign-up
  (`FirstRun`) and quietly at the end of «Εγώ» (ANR's picks 1, 2 and 3).
- Copy lives in the `Landing` namespace in every locale, in the canonical
  terms. No invented numbers, members or testimonials.
- Motion: CSS only (theme variables), and none of it under reduced motion:
  stories do not advance on their own, the phone keeps its first screen.

## Rationale
The stories match how people already consume short content on a phone; the
dark first screen gives tablets and desktops one clear impression, and the
form stays one tap away instead of competing with the pitch. Keeping
`/login` and `/register` as routes avoids breaking emails, invites and the
`next` redirect of `AuthGuard`.

## Alternatives Considered
A «half and half» (form always open beside the pitch), C «two doors» (one
screen of tiles with phone tabs) and D «stories everywhere» (stories on big
screens too): ANR preferred B and then B+ with the drawer form.

## Consequences
- Guests no longer get a redirect from `/`; crawlers still get the noscript
  overview there.
- The photo `public/landing-gym-floor.jpg` is from Unsplash (photo
  1534438327276-14e5300c3a48, Unsplash License, free for commercial use, no
  attribution required). Replace it with Palee's own box photos when we have
  them.
- `AuthConsole` remains as the plain centred page for tests and any future
  standalone use.

## Implementation Notes
- The form opens after the first paint on `/login` and `/register`: `Dialog`
  is a portal and the server cannot render it (hydration).
- React listens for `webkitAnimationEnd` in jsdom; the story test dispatches
  that name.
- e2e: `e2e/guest-landing.spec.ts` runs with reduced motion, because the
  bouncing «See more» is never "stable" for Playwright's click.
