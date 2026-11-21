# Digital SAT question style guide (for Practice generation)

Sources: College Board Educator Question Bank API (stratified sample of ~500 items read for patterns, none reproduced)
and the Assessment Framework for the Digital SAT Suite (satsuite.collegeboard.org/media/pdf/assessment-framework-for-digital-sat-suite.pdf).

## Section facts
- R&W: 2 modules × 27 (32 min, ~71 s each). Every question is discrete, 4-option MC, one passage or a Text 1/Text 2 pair.
- Math: 2 modules × 22 (35 min, ~95 s each). ~75% MC, ~25% student-produced response (SPR). Desmos available.
- R&W domains: Craft and Structure ~28%, Information and Ideas ~26%, Standard English Conventions ~26%, Expression of Ideas ~20%.
  Within a module questions are grouped by skill, easiest → hardest. Math modules go easiest → hardest overall.
- Math domains: Algebra ~35%, Advanced Math ~35%, Problem-Solving and Data Analysis ~15%, Geometry and Trigonometry ~15%.
- Passages 25–150 "words" (CB counts 6 characters as a word); subjects: literature, history/social studies, humanities, science;
  no outside knowledge. Graphics in R&W: tables, bar and line graphs only, no calculation. ~30% of Math in context, mostly ≤ 50 words.
- Distractors each represent a common error or misconception; similar length and grammar to the key; key position spread evenly A–D.

## Reading and Writing
Passages: dense, neutral, expository; name a real-sounding researcher/artist, give a finding, then a qualification.
Literature/poetry/history excerpts open with "The following text is from/adapted from [Author]'s [year] [novel/poem] Title." Blank = "______".
Distractor families: not mentioned · overreach (beyond the study's scope) · contradicts a detail · true detail, wrong role · misreads the graph / doesn't support the claim.

Craft and Structure
- Words in Context: "Which choice completes the text with the most logical and precise word or phrase?" (~85%); or "As used in the text, what does the word "X" most nearly mean?" (literature). 35–90 words, one blank; four single words/short phrases, same part of speech. Easy: common words, distinct meanings. Hard: Tier-2/3 academic words, all plausible, inference often after a colon.
- Text Structure and Purpose: "Which choice best states the main purpose of the text?" / "…best describes the function of the underlined sentence in the text as a whole?" / "…the overall structure of the text?" 65–130 words; choices are infinitive phrases ("To emphasize…", "To argue…"), 10–20 words.
- Cross-Text Connections: Text 1 + Text 2 (115–170 words total; Text 2 often a new study complicating Text 1). "Based on the texts, how would [the author of Text 2] most likely respond to [the underlined claim] in Text 1?" / "…both authors would most likely agree with which statement?" Choices are full sentences, 13–25 words ("They would argue…").

Information and Ideas
- Central Ideas and Details: "Which choice best states the main idea of the text?" (also "According to the text, why…", "Based on the text, what is true about…", "Which question does the text most directly attempt to answer?"). 50–130 words; choices 11–19 words.
- Command of Evidence (textual): "Which finding, if true, would most directly support/weaken the [underlined] claim?" / "Which quotation from [work] most effectively illustrates the claim?" Evidence connects by inference, not restatement.
- Command of Evidence (quantitative): a table or graph + 40–130-word text ending in a claim. "Which choice most effectively uses data from the table/graph to complete the statement?" Distractors use real but irrelevant numbers or support the opposite claim.
- Inferences: "Which choice most logically completes the text?" 60–125 words ending "…suggesting that ______". Choices 13–25 words; Hard keys are cautious consequences, distractors overreach.

Standard English Conventions (stem: "Which choice completes the text so that it conforms to the conventions of Standard English?"; 25–65 words)
- Boundaries: the same words with different punctuation (created / created: / created, / created;), conjunctive adverbs, appositive commas, question vs statement.
- Form, Structure, and Sense: forms of one verb (tense, agreement, finite vs nonfinite), possessives, pronoun number; Hard: dangling-modifier rewrites.

Expression of Ideas
- Rhetorical Synthesis: "While researching a topic, a student has taken the following notes:" + 5–6 bullets (40–100 words). "The student wants to [goal]. Which choice most effectively uses relevant information from the notes to accomplish this goal?" Choices: one sentence each, 15–25 words, all accurate to the notes; only the key meets the goal.
- Transitions: "Which choice completes the text with the most logical transition?" 35–70 words, blank at a sentence start; four transitions + comma from different logic families; Hard: close pairs (That said / Nevertheless).

Difficulty (R&W): harder = denser text, longer and more abstract choices (median 11–13 words Easy → 18–23 Hard), partly-true distractors, more inference steps.

## Math
Stem carries everything; often an equation on its own line, then "The given equation…", then the question.
Stem phrases: "What is the value of…?", "Which of the following…", "Which expression is equivalent to…", "In the xy-plane, …",
"The function f is defined by f(x) = …", "…where a, b, and c are constants", "Which equation correctly expresses c in terms of b and f?",
"What is one of the solutions to the given equation?", "How many distinct real solutions…", "…is closest to…".
Units in the question ("What is the area, in square centimeters, …"); conversions on their own line ("1 fathom = 6 feet"). Short realistic contexts.
MC numeric choices listed ascending; distractors match specific errors. SPR ~25% (Easy ~9%, Medium ~32%, Hard ~36%), most in percentages, ratios/units, linear equations, circles;
answers are integers, decimals without a leading zero (.5), or fractions (31/2), up to 5 characters (6 with a minus sign).
Graphs/tables: scatterplots and two-variable data, lines/angles/triangles and right-triangle trig (figures), probability (two-way tables).
Difficulty: Easy one step, clean numbers; Medium two steps or a context to translate; Hard unknown constants, structural reasoning (equivalence, number of solutions), radians/unit circle, multi-step percent, fractional SPR answers.
Skills: Algebra (linear equations in 1 and 2 variables, linear functions, systems of 2 linear equations, linear inequalities); Advanced Math (equivalent expressions, nonlinear equations and systems, nonlinear functions);
PSDA (ratios/rates/units, percentages, one-variable data, two-variable data, probability, inference from samples and margin of error, evaluating statistical claims); Geometry and Trigonometry (area and volume, lines/angles/triangles, right triangles and trigonometry, circles).
