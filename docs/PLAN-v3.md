# SAT Tracker v3 plan (2026-11-06)

Grounded in two research passes (College Board My Practice, UWorld, PrepScholar, Magoosh, Khan, Acely, Oura, Strava; Apple HIG generative AI, sidebars, progress, alerts; ChatGPT/Claude chat conventions).

## Student feedback this round
Loading screen for the whole dashboard while AI writes; warn when a weaker model is picked; correct-answer bar into the question header, bigger; AI chat must look like an AI app; switching sections closes the focused question; collapsible sidebar; Tutor page too small with empty space; timeline filters (right/wrong, section, more) that also drive next/previous; plan overview and dashboards not comprehensive.

## Decisions
1. **Loading**: while `Store.progress[sid]` exists the test page is one determinate screen: progress bar, "Explaining question 34 of 98", then "Writing your review". (HIG: determinate when length is known; specific labels.)
2. **Model warning**: inline caption with a warning symbol under the picker when Apple Intelligence is chosen, saying the trade-off. No alert (HIG alerts).
3. **Question header**: "Question 14", section/module, then the result in large type: Correct **A**, You chose **D** (crossed out A, B), then difficulty · skill · domain. Bottom bar removed; the screenshot gets the height. "n of m" reflects the active filter.
4. **AI chat** (question panel and Tutor page share one kit): assistant replies as plain full-width text (markdown: bold, lists), user turns as right-aligned bubbles, typing dots before the first reply, copy under replies, rounded composer with the send arrow inside, centred empty state with suggestion chips, "AI can make mistakes" caption. Tutor column max ~760 pt, 15 pt text.
5. **Focus closes** on any section/tab change.
6. **Sidebar**: NavigationSplitView column visibility, toolbar toggle, View menu command.
7. **Filters** (UWorld/Acely pattern): Result segmented (All, Wrong, Right, Not graded) + chips: Section, Module, Difficulty, Flagged, Guessed, Over pace, Topic. Non-matching bars fade; the question view steps only through the filtered list.
8. **Dashboards** (score + contributors, Oura; College Board domains): overview shows per-section correct/total and time, result split bar, topic accuracy in two columns (R&W | Math), slowest questions, next actions (Question Bank drill for weakest topics, flashcards). Today: countdown, today's tasks with minutes, latest test with change, weakest 3 topics with status, week grid of study minutes and streak, next practice test, cards due. Plan: header (test date, days left, target, % done), phase strip, current week expanded into day rows, month calendar, focus topics with accuracy, upcoming tests. Wide windows fill a grid; no single narrow column.

## Ownership (parallel agents, disjoint files)
- A Review.swift: 1, 5, 7, overview part of 8.
- B Views.swift (not QuestionChat): 3 and the filtered order (`QuestionView(keys:)` already exists).
- C Home.swift + App.swift: 2 (Settings), 6, Today + Plan part of 8.
- D new ChatKit.swift + Coach.swift + Onboarding.swift: 4 (moves QuestionChat out of Views.swift), 2 (onboarding tutor step).
