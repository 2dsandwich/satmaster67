# SAT Tracker → SAT tutor: plan (2026-11-06)

Built from research (SAT tutoring practice, fitness/health dashboards, College Board data, the user's other apps).
Goal: an app any SAT student can use with no setup knowledge, that feels like an Apple app.

## Principles
- **One hero per screen**, with a band word (Oura/Whoop). Contributors under it. Charts titled with their takeaway (HIG).
- **Overview vs detail**: overview = glanceable cards in a grid that fits ~1100×760 without page scroll; detail one click away.
  Long lists scroll inside their own card, never the page.
- **Type scale** (SF Pro / SF Pro Rounded for numbers): hero 56 bold rounded · title 26 light (onboarding, Ardia) ·
  section 20 semibold · card title 13 semibold uppercase-free · value 24 bold rounded · body 13 · caption 11 secondary.
- **Layout tokens shared with MONEY!/Moneybag**: inset 16, card radius 26, inner radius 10 (= 26 − 16), gap 16, rows 32.
- Glass only on controls that float (menu controls, chat button, floating timer). Content cards are plain surfaces.
- Motion: spring(0.42, 0.8) for opens (Island), smooth 0.24 for resizes, 0.12–0.15 s fades; reduce-motion → none.
- Never color alone: icons + labels with every state color. Wrong = solid red, right = light green.

## Grading (replaces the screenshot guesser)
Source of truth, in order: **Official** (imported from My Practice) → **You** (your mark) → **Estimate** (Claude reading
the screenshot; labelled "estimate"). Apple's model never grades (it guessed wrong in testing). The badge shows the source.

## Official data import
- My Practice "Score Details" lists each question with correct answer + your answer; also total/section scores.
- College Board terms forbid scraping, so the app only reads the page the student is looking at, when they choose to:
  1. Paste: ⌘A ⌘C on the score page → "Import from My Practice" → preview → apply.
  2. Optional Chrome extension: a button on My Practice sends the same page text to the app (127.0.0.1, MV3 service worker).
- Parser: deterministic first; if it finds too few questions, the AI extracts them; always a preview the student confirms.
  Raw text kept so it can be re-read later. PDFs are not used (nonadaptive, don't match Bluebook module 2).
- Imported question text + official answer feed the explanation, so explanations start from the real question.

## AI without setup
Default: Apple Intelligence on device (free, private; text only, 4K context; uses imported text or OCR of the screen).
Optional: Claude key for richer explanations and reading screenshots. Onboarding explains both in plain words.

## Screens
Sidebar (Apple-style): **Today · Plan · Tests · Flashcards · Words · Settings**, countdown at the bottom.
- **Onboarding** (first launch, progress pills): Welcome → Test date (official dates or a target month) + target score →
  Study days & minutes → Tutor (Apple Intelligence / Claude) → Screen permission (live status) → Official answers (optional)
  → Your plan.
- **Today**: countdown hero (days, date, target vs latest score) · today's tasks (one primary action) · week streak dots ·
  score trend with goal line · weakest skills (contributors) · flashcards due (new + learning + due).
- **Plan**: phases across the weeks left (Diagnose → Build → Practice tests → Final week), week grid of day tasks.
  Deterministic scheduler (works offline); the tutor adds a short note. Re-plans when tests are taken or dates change.
- **Test review**: header with score hero + band + section scores; Overview / R&W / Math. Two columns, no page scroll:
  left = coach headline, contributors (accuracy, pace, careless, hard), fix next; right = module cards with
  **splits chart** (time per question, pace line, fastest/slowest marked) and a **hypnogram-style order strip**
  (lanes Right / Wrong, total above, per-lane time summary).
- **Question**: screenshot, official/you/estimate badge, answer, what went wrong, solution, words; MONEY!-style chat.
- **Flashcards**: words + missed-question cards, SM-2 scheduling, 3D flip on a spring, Again/Hard/Good/Easy with the next
  interval on each button, keyboard (space, 1–4).

## Review rounds
4 rounds of independent visual review against a rubric (readability, hierarchy, visual clarity, uniformity,
onboarding clarity for a non-technical student, Apple feel), fixes between rounds.

## User flows (end to end)
1. **First launch** → onboarding (7 steps, back/next, can't get stuck: every step has a default or Skip) → Today.
2. **Day to day** → Today shows the day's tasks from the plan → a task opens what it needs:
   practice test → "Open Bluebook" + menu bar Start (auto-start also works); review → the test's review;
   flashcards → Flashcards; skill drill → College Board Question Bank link filtered to the skill (external, official).
   Tasks tick off automatically when done (test finished, cards studied, review opened ≥ 2 min), or by hand.
3. **Taking a test** → menu bar / floating timer exactly as now (unchanged, proven) → Finish → review opens.
4. **After a test** → review shows times at once; grades = estimate (Claude) or blank (Apple) → banner
   "Add official answers" → paste / extension → preview → apply → grades become Official, explanations rerun only for
   questions whose grade changed → debrief → flashcards for misses → plan re-balances (weak domains get more drill).
5. **Test date passes / changes** → Settings › Goal; past deadline → Today asks for the next date (official list).

## Study plan scheduler (deterministic, offline)
Inputs: deadline, study weekdays, minutes per day, tests already taken (Practice 4–11), latest score + weak domains.
- Weeks left W. Phases: **Diagnose** (first study day, if no test taken: full test), **Build** (until W−2),
  **Practice** (last 2 weeks before taper: tests every ~7 days), **Taper** (final 7 days: no full tests, light review,
  rest the day before). If W < 2: Diagnose → Practice → Taper compressed.
- Full tests: aim min(remaining Practice tests, 1 per week in Build when W ≥ 6, else every 5–7 days), never in the
  final 6 days, never two within 3 days. Each full test is followed next study day by **Review** (always).
- Other study days fill minutes in this order: Review of unreviewed misses (≈ 1.5 min each) → Flashcards (due count ×
  0.2 min, ≤ 15 min) → **Skill drills** on the 2 weakest domains (by accuracy, Official > estimate; before any test:
  balanced by official domain shares) in 20-minute blocks → timed module practice in Practice phase.
- Output: [Day: [Task(kind, title, minutes, link)]]; recomputed on launch, after each test, and when Goal changes.
  Completed tasks are remembered by date + kind so recompute never loses ticks.
- The tutor (AI) writes one sentence per week ("This week: Advanced Math, because 5 of 8 misses were there").
  If no AI, a template sentence from the same numbers.

## Empty & error states (every screen)
- No tests yet: Today's hero is the countdown; the plan's first task is the diagnostic; review/score cards show
  "Your first practice test fills this in" with the SAT Practice 4 button.
- No AI available (Apple Intelligence off, no key): explanations show a single "Set up a tutor" button → Settings.
- Screen Recording denied: menu bar icon shows a warning; Start explains with an Open System Settings button.
- No deadline: plan assumes 8 weeks and Today shows "Set a test date".
- Import found nothing: preview shows "Couldn't read answers from this page" + keep raw text, nothing applied.

## Migration
Existing sessions load unchanged (new fields optional). Old Japanese explanations stay until "Redo Explanations".
Profile is created by onboarding; existing users see onboarding once (pre-filled from data where possible).
