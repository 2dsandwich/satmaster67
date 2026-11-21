# Explanations v2 (2026-11-06)

## Problem (student, on R&W M1 Q3)
- The same facts appear 2–3 times: "you crossed out C" in the header, in the headline and again in the detail; the clue "continuously worked" in the headline, in step 1 and in "Reading the question".
- No single line says the key idea, so it's hard to know what to take away.
- The word list pads with words the student knows (legislator, continuously).

Cause: the output format has six overlapping fields (coach_line, trap, solution, wording, time_note, vocab) with no rule that a fact appears once, and the header already shows the answers and time.

## New output contract (one job per field)
| Field | Job | Limit |
|---|---|---|
| key_point | The one idea that unlocks this question, as a rule to remember | 1 sentence, ≤ 14 words |
| trap | Why the student's choice (or the tempting choice) fails | 1–2 sentences |
| solution | Steps to the answer; each step a new action; ends at the answer | 2–4 steps |
| coach_line | A habit for next time, reusable on other questions | 1 imperative sentence, ≤ 15 words |
| wording | Only when the question's own wording is the trap (NOT, "most logically", "value of") | else empty |
| vocab | Words a strong student reading in a second language may not know | ≤ 4, none already explained |
| student_answer | Letter or value, crossed-out choices in parentheses: "A (crossed out C, D)" | exact format |

Global rules: each fact appears once across all fields. Never restate the chosen answer, the correct answer or the time (the screen shows them). Short sentences, common words.

## Screen (right column, top to bottom)
1. Key point: large type, every question.
2. Wrong only: "Why A doesn't work": trap, cause tag, "Next time:" habit.
3. Solution steps.
4. Reading the question: only if wording is non-empty.
5. Words.
Old explanations (no key point) keep the old layout until explained again.

## Rollout
Explain Practice 10 again with Claude (official right/wrong stays final), then check a few questions on screen.
