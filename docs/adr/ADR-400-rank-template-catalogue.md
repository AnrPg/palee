# ADR-400: A researched catalogue of rank templates, new workout kinds, and skills ticked one by one
Date: 2026-11-03
Status: Accepted

## Context
ADR-377 shipped belts and levels with three hard-coded Greek templates (BJJ adult belts, a 7-belt karate ladder, gymnastics levels 1–10). The product owner asked:
- whether «Επίπεδα ενόργανης» is really gymnastics. "Gymnastics" can mean artistic (ενόργανη), rhythmic (ρυθμική), trampoline, acrobatics, freestyle or parkour, depending on the skills;
- for many more sports: martial arts (jiu-jitsu, kung fu, Krav Maga, taekwondo and others), dance (ballet, contemporary, salsa, bachata, hip-hop, R&B, reggaeton, heels), aerial, pole, skateboarding, parkour, acrobatics, CrossFit, metcon, HYROX and heavy lifting;
- for the real grading systems, where they exist, with a curriculum of skills per level.

Later (same day) the product owner added:
- where no official levels exist, Palee may define its own from the researched skills;
- a template is only a starting point that each box or solo coach turns into its own curriculum;
- the feature should cover what coaches and members need around a curriculum.

The research, with sources, is in `docs/research/rank-curricula-research-2026-11-03.md`.

## Decision
- **Catalogue** (`Palee.Ranks.Domain.LadderTemplates`, one module per family): 75 templates. Each has a key, an English name, a discipline (a workout type), a style (`belt|level`), a **`source`**, a short note on the system it follows, and ranks. `source` is `federation` when the levels are a federation's or school's system (IBJJF, IJF/European judo, Kukkiwon, Aikikai, WAKO, USA Gymnastics, British Gymnastics, Swim England, NICAS, HYROX, the RAD structure…) and `palee` when no official levels exist and Palee built its own from the researched skills (salsa, heels, pole, calisthenics, parkour, CrossFit levels, contemporary grades, bouldering by V-grade, the generic 7-belt karate and kung fu sash ladders…). The `system` line is a short label (at most 80 characters); the long source notes are in the research doc. Each rank lists the skills tested to reach it: up to 20, each at most 120 characters, written so a coach can tick them, with no commas (the web editor splits on commas). Minimum days or classes are set only where a federation states them (IBJJF days in grade, Aikikai practice days, WAKO months, Shotokan/judo/taekwondo intervals of the most common bodies).
- **Template names follow the system without claiming it.** Names describe the structure ("Ballet graded levels (RAD structure)", "Latin American medal levels"), and the skills are Palee's own wording of step and technique names, never copied syllabus text. The templates are not affiliated with or endorsed by the RAD, ISTD, IDTA, Cecchetti, IBJJF, Kukkiwon, USA Gymnastics, British Gymnastics, Swim England, NICAS, HYROX or any other body named in the notes.
- **Languages**: the texts are English message ids of a new gettext domain, `rank_templates`, in every API locale. Greek has every template name, `system` line, rank name and skill. The other ten languages have every template name, every `system` line and the shared rank names (colours, compound colours such as «Γκρι-λευκή», and numbered names such as «Επίπεδο %{n}», «%{n}ο kyu», «%{n}ο dan»); their skills fall back to English until they are translated. Exam names that are also generic words («Intermediate», «Advanced 1», «Primary») carry `msgctxt "exam"`: an RAD or ISTD exam keeps its English name with a gloss («Intermediate (ενδιάμεσο)»), while a salsa «Intermediate» reads «Μέσο επίπεδο». In the catalogue such a name is `{:exam, name}`, and `Palee.Localization.translate/4` takes `{context, message_id}` for it. `GET /admin/rank-ladders?locale=` returns the catalogue in that language, and `POST /admin/rank-ladders {template, locale}` copies the ranks in that language. When no locale is given, the language is Greek, as before ADR-400. The `templates` items now have a schema (`RankTemplate`) in OpenAPI.
- **The original three keep their keys.** `bjj_adult` keeps its Greek names and gains skills, and its minimum days now follow the IBJJF: purple 730 (2 years at blue), brown 540, black 365, up to 6 black-belt degrees. Before, they were shifted by one belt. `karate_kyu` now uses the new `karate` kind and gains skills. `gymnastics_levels` stays a generic 1–10 ladder with no skills, named «Γυμναστική: επίπεδα 1-10»; the artistic, rhythmic, trampoline, tumbling and acrobatics ladders are now separate templates. Ladders boxes already stored never change: a template is copied when a ladder is created.
- **Gymnastics is split into kinds.** New workout kinds (ADR-275 catalogue, `BoxProfilePolicy` disciplines, web labels in every locale):
  - gymnastics family: `artistic_gymnastics` (ενόργανη), `rhythmic_gymnastics` (ρυθμική), `trampoline_tumbling`, `acrobatics`, `parkour` (with freerunning). The box profile gets a "Gymnastics & acrobatics" group for them;
  - combat: `judo`, `karate`, `taekwondo`, `kung_fu` (with wushu and Wing Chun), `krav_maga`. `martial_arts` now reads "Martial arts (aikido, capoeira, other)";
  - dance: `ballet`, `contemporary_dance`, `latin_dance` (salsa, bachata, kizomba, Latin medals), `street_dance` (hip-hop, commercial/R&B, breaking, reggaeton, heels);
  - outdoor: `skateboarding`.
  
  The existing `gymnastics` kind stays for CrossFit-style bodyweight gymnastics, and `calisthenics` takes street workout and freestyle. The DB column is a string (ADR-275), so new kinds need no migration.
- **Skills ticked one by one** («Δεξιότητες»): a new tenant table `rank_skill_checks` (migration `20270615000000_rank_skill_checks`; forced RLS, tenant trigger, a unique key on person, rank and skill, cascades with the rank). `PUT /staff/clients/:user_id/ranks/skills {rank_id, skill, checked?, checked_on?, note?}` ticks a skill or unticks it (`checked: false`). It needs `manage_coaching`, so a coach reaches their own clients (ADR-100), and only a skill on the rank's list can be ticked (`unknown_skills`). Progress gains `skills_checked` (skill, date, note) and `all_skills_checked`. `ready` keeps meaning that the counted requirements are met. The person sees their ticks in their own standing. Ticks belong in the tenant data policy, the tenancy audit and the GDPR export.
- **Who may edit a curriculum**: unchanged (ADR-099): the ladder routes need `manage_settings` or `manage_workouts`. So the owner and admins can edit, every coach can edit (coaches hold `manage_workouts`), and so can a solo coach, who is the owner of a `provider_kind: coach` organisation. The controller test covers a coach copying a template.

## Rationale
- The repo already translates server-side catalogues with gettext domains (emails, receipts, calendar). The other choice was 2,300 skill strings in 12 web message files, which would make the web bundle heavier on every page for a settings screen.
- Using English message ids means a missing translation falls back to readable English, never to a key.
- `source` lets the picker and the research doc separate the systems a box can cite from Palee's own suggestions. This matters to coaches who grade for a federation.
- Ticking skills one at a time is the core of a curriculum. Without it, a coach can only tick skills on the day of a promotion, and a member cannot see what is left.

## Alternatives Considered
- Message keys translated on the web (as the three template names were): rejected for size, see above.
- A single vague "gymnastics" discipline with sub-templates: rejected. Stats, badges and the box profile need to tell artistic, rhythmic and trampoline training apart.
- Folding skill ticks into `rank_awards.skills_checked`: rejected. An award marks a promotion and cannot record a skill learnt in week 3 of 40.
- A "ready for promotion" list across members: deferred. It needs class attendance for many members in one query, and `Scheduling.list_class_history` runs per person. A batch attendance count belongs in Scheduling first.

## Consequences
- The template picker grows from 3 chips to 75 entries. The web keeps the existing chip list as a stopgap, now filled from the server in the page's language. The real picker, the curriculum editor, coach ticking and the member's progress screens are designed as mockups with alternatives for the product owner first.
- Translators: skills in ar, ru, de, es, pt-PT, he, it, bg, nl and fr fall back to English (`rank_templates.po` lists them with empty `msgstr`).
- Adding a template: add it to its family module and its texts to `rank_templates.pot` and the Greek `.po`. `LadderTemplatesTest` fails on a missing Greek skill, a missing template name or `system` line in any language, a comma in a skill, or an invalid ladder.

## Implementation Notes
- Catalogue research was split: combat sports, gymnastics, dance, fitness and outdoor in this branch, plus two research helpers. Fitness and endurance added strongman, kettlebell, running, cycling, rowing, pilates, mobility, HIIT and general strength; dance and acro added tap, jazz, Cecchetti, Vaganova, kizomba, dance fitness, aerial yoga, wrestling and sambo. Every federation claim was fact-checked against its source after drafting, and all fixes are applied (listed per sport in the research doc).
- Greek decimals are written with a point (1.5) because a comma would split a skill in the editor.
