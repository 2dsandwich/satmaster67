import Foundation

/// One official SAT skill and how College Board writes its questions, from docs/SAT-STYLE.md and docs/SAT-MATH-STYLE.md.
/// The writer gets only the specs of the skills in its batch.
struct Skill: Hashable {
    let section: String, domain: String, name: String
    var weight = 1.0         // its share of the domain's questions in a module
    var spr = 0.0            // Math: share of student-produced responses for this skill
    let stems: String        // the official question wording
    let form: String         // passage or stem: what it holds and how long it is
    let choices: String      // how the choices are built and where the wrong ones come from
    let levels: String       // what makes a question Easy, Medium or Hard
    var notes = ""           // figures, tables, Desmos

    var spec: String {
        ["Stems: " + stems, "Form: " + form, "Choices: " + choices, "Difficulty: " + levels,
         spr > 0 ? "About \(Int((spr * 100).rounded()))% of these are student-produced responses." : section == Sec.math ? "Always multiple choice." : "",
         notes].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

extension Practice {
    nonisolated static let rw = "Reading and Writing"
    nonisolated static let tiers = ["Easy", "Medium", "Hard"]

    static func skills(_ section: String, _ domain: String? = nil) -> [Skill] {
        skills.filter { $0.section == section && (domain == nil || $0.domain == domain) }
    }

    /// Rules for every question in a section.
    static let rules: [String: String] = [
        rw: """
        READING AND WRITING. Every question is discrete four-option multiple choice on one passage (or a Text 1 / Text 2 pair). \
        Passages are dense, neutral and expository, about literature, history/social studies, humanities or science, and need no \
        outside knowledge. A typical science or humanities passage names a real-sounding researcher or artist, gives a finding or \
        claim, then a qualification. Word counts count words as College Board does (about 6 characters each). \
        A blank in the passage is written ______ (six underscores). An underlined part of the passage is written <u>like this</u>. \
        Literature, poetry and historical excerpts are your own writing in the period's style, attributed to an invented author, \
        and open with one line such as "The following text is from [Author]'s [year] novel [Title]." or "The following text is \
        adapted from [Author]'s [year] speech [Title]." then a blank line, then the excerpt. \
        Every wrong choice represents one common error: not mentioned in the text, overreach beyond what the text or study shows, \
        contradicts a detail, a true detail in the wrong role, or misreads the data / doesn't support the claim. All four choices \
        have about the same length and grammar. \
        Difficulty: Easy = plain text, short concrete choices (median 11 to 13 words for sentence choices), one inference step. \
        Medium = more abstract text, one partly-true distractor. Hard = denser text, longer and more abstract choices (18 to 23 \
        words), partly-true distractors, several inference steps.
        """,
        Sec.math: """
        MATH. The stem carries everything. An equation or system sits on its own line, followed by "The given equation…" or \
        "In the given system…". Put a short realistic context (mostly 50 words or fewer, about 30% of questions) in the passage \
        field, the question line in the question field; with no context the passage is empty. \
        Stem phrases: "What is the value of…?", "Which of the following…", "Which expression is equivalent to…", \
        "In the xy-plane, …", "The function f is defined by f(x) = …", "…where a, b, and c are constants", "k is a positive \
        constant", "for x > 0", "Which equation correctly expresses c in terms of b and f?", "What is one of the solutions to \
        the given equation?", "How many distinct real solutions…", "Which of the following is closest to…". \
        Notation: thousands commas (1,150) but none in years; decimals in stems keep the leading zero (0.49); % after numbers; \
        units spelled out with the abbreviation on first use, "centimeters (cm)"; the question names the unit ("What is the area, \
        in square meters, of…"); conversions in parentheses at the end, "(1 fathom = 6 feet)". Write money as "12 dollars", \
        never with a dollar sign (the dollar sign marks math). \
        Multiple choice: numeric choices in ascending order (values with π or √ by size; ordered pairs by x, then y). \
        Expression or equation choices form a 2×2 grid of two error features (coefficient right/wrong × constant right/wrong, \
        < vs >, roles swapped). Fixed sets where they fit: "Exactly one / Exactly two / Infinitely many / Zero"; "I only / II only / \
        I and II / Neither I nor II". Wrong choices come from: another quantity in the problem (an intermediate value, the other \
        variable, a given number; about 45%), a mis-built equation (wrong inverse operation; about 20%), a swapped feature (sign, \
        inequality direction, at least vs at most; about 15%), or a reciprocal, complement, squared value or decimal shift. \
        Student-produced response (no choices): the answer is an integer, a fraction (31/2) or a decimal without a leading zero \
        (.5), at most 5 characters (6 with a minus sign); never a %, unit, π or √: ask for a constant instead ("…is k√3 \
        centimeters, where k is a constant. What is the value of k?"). If several forms are accepted, list them separated by \
        commas: "49/2, 24.5"; for a repeating decimal the fraction plus 4-character decimals: "2/43, .0465, .046". State \
        rounding ("to the nearest tenth"). \
        No figures can be shown: describe a figure fully in words (vertices, right angles, side lengths, angle measures as x°, \
        parallel lines) and write a table as lines after the text: a title line, then a header row and one line per row, cells \
        separated by " | ", with a Total row or column where the SAT would have one. A scatterplot is given by its line of best \
        fit and a few points. \
        Difficulty: Easy = one step, clean numbers. Medium = two steps, or a context to translate. Hard = unknown constants, \
        structural reasoning (equivalence, number of solutions), radians and the unit circle, multi-step percent, fraction \
        answers.
        """,
    ]

    private static func r(_ domain: String, _ name: String, _ weight: Double, stems: String, form: String, choices: String, levels: String) -> Skill {
        Skill(section: rw, domain: domain, name: name, weight: weight, stems: stems, form: form, choices: choices, levels: levels)
    }
    private static func m(_ domain: String, _ name: String, spr: Double, stems: String, choices: String, levels: String, notes: String = "") -> Skill {
        Skill(section: Sec.math, domain: domain, name: name, spr: spr, stems: stems, form: "a stem, often with an equation on its own line; a context only where the skill uses one.",
              choices: choices, levels: levels, notes: notes)
    }

    /// Every official skill, in module order: Reading and Writing questions are grouped by skill in this order.
    static let skills: [Skill] = [
        // Reading and Writing: Craft and Structure
        r("Craft and Structure", "Words in Context", 4,
          stems: "\"Which choice completes the text with the most logical and precise word or phrase?\" (about 85%); for a literature excerpt, \"As used in the text, what does the word \"X\" most nearly mean?\" with the word underlined in the text.",
          form: "35 to 90 words with exactly one blank ______ (or the underlined word).",
          choices: "four single words or short phrases, the same part of speech and form. Wrong ones: right tone but wrong meaning, fits only part of the context, the opposite of the clue.",
          levels: "Easy: common words with clearly different meanings. Hard: Tier 2 and 3 academic words, all four plausible, the clue an inference often after a colon or a contrast."),
        r("Craft and Structure", "Text Structure and Purpose", 2,
          stems: "\"Which choice best states the main purpose of the text?\", \"Which choice best describes the function of the underlined sentence in the text as a whole?\" or \"Which choice best describes the overall structure of the text?\"",
          form: "65 to 130 words; for the function stem, one sentence is underlined with <u>…</u>.",
          choices: "infinitive phrases of 10 to 20 words (\"To emphasize…\", \"To argue…\", \"To introduce…\"). Wrong ones: the role of another sentence, too broad, a purpose the text never takes.",
          levels: "Easy: the purpose is stated. Hard: the purpose is implied, choices differ by one verb or one qualifier."),
        r("Craft and Structure", "Cross-Text Connections", 1,
          stems: "\"Based on the texts, how would [the author of Text 2 / the named researcher] most likely respond to [the underlined claim / \"…\"] in Text 1?\" or \"Based on the texts, both authors would most likely agree with which statement?\"",
          form: "two texts, each starting with a line \"Text 1\" or \"Text 2\", 115 to 170 words in total; Text 2 often reports a newer study or view that complicates or qualifies Text 1.",
          choices: "full sentences of 13 to 25 words (\"By arguing that…\", \"They would argue…\"). Wrong ones: the view of the wrong text, agreement where Text 2 disagrees, overreach.",
          levels: "Easy: plain disagreement. Hard: Text 2 qualifies rather than rejects; the key is a cautious partial agreement."),
        // Information and Ideas
        r("Information and Ideas", "Central Ideas and Details", 2,
          stems: "\"Which choice best states the main idea of the text?\", \"According to the text, why…?\", \"Based on the text, what is true about…?\" or \"Which question does the text most directly attempt to answer?\"",
          form: "50 to 130 words.",
          choices: "sentences of 11 to 19 words. Wrong ones: a true detail that is not the main idea, too broad or too narrow, not mentioned.",
          levels: "Easy: the idea is stated in one sentence. Hard: literature or dense argument; the idea is spread across the text."),
        r("Information and Ideas", "Command of Evidence: Textual", 1.5,
          stems: "\"Which finding, if true, would most directly support the [researcher's] claim?\", \"…would most directly weaken the underlined claim?\" or, after a literature claim, \"Which quotation from [the poem/novel] most effectively illustrates the claim?\"",
          form: "50 to 130 words ending in a claim or hypothesis (sometimes underlined); a quotation question states a claim about a work and the choices are quotations from it.",
          choices: "findings or quotations, each a sentence. The key connects by inference, not restatement. Wrong ones: support the opposite, irrelevant, restate the claim without testing it.",
          levels: "Easy: one variable, direct support. Hard: the key tests a specific mechanism; distractors are plausible but off-target."),
        r("Information and Ideas", "Command of Evidence: Quantitative", 1.5,
          stems: "\"Which choice most effectively uses data from the table to complete the statement?\" (or \"…to support the claim\", \"…to illustrate the claim\", \"from the graph\").",
          form: "40 to 130 words ending in a claim, often with a blank ______, then a table written as lines: a title line, a header row and data rows, cells separated by \" | \". No calculation beyond reading and comparing values.",
          choices: "sentences that cite values from the table. Wrong ones: real but irrelevant numbers from the table, values that support the opposite claim, true statements that don't address the claim.",
          levels: "Easy: one column, one comparison. Hard: two variables compared across rows; the key is the only choice that fits the claim's exact condition."),
        r("Information and Ideas", "Inferences", 2,
          stems: "\"Which choice most logically completes the text?\"",
          form: "60 to 125 words ending in an unfinished sentence such as \"…, suggesting that ______.\"",
          choices: "13 to 25 words each. Hard keys are cautious consequences; wrong ones overreach, reverse the logic or bring in an outside idea.",
          levels: "Easy: one step from a stated fact. Hard: combines two findings; every choice sounds reasonable."),
        // Standard English Conventions
        r("Standard English Conventions", "Boundaries", 1,
          stems: "\"Which choice completes the text so that it conforms to the conventions of Standard English?\"",
          form: "25 to 65 words with one blank where the punctuation decision is. The blank stands for the whole choice: the word the choices repeat is not also in the passage (\"recur throughout the ______ the prophetic dream\" with choices \"corpus;\" / \"corpus,\"; never \"the corpus ______\").",
          choices: "the same words with different punctuation (\"created\" / \"created:\" / \"created,\" / \"created;\"), conjunctive adverbs (\"; however,\" / \", however,\"), appositive and nonessential commas, dashes, question vs statement endings. Wrong ones: comma splice, fused sentence, a colon or semicolon that splits a clause.",
          levels: "Easy: two short clauses to join. Hard: long sentences with embedded clauses, supplements set off by dashes, a list after a colon."),
        r("Standard English Conventions", "Form, Structure, and Sense", 1,
          stems: "\"Which choice completes the text so that it conforms to the conventions of Standard English?\"",
          form: "25 to 65 words with one blank. The blank stands for the whole choice; the word is not also printed next to it.",
          choices: "four forms of one word: verb tense and subject-verb agreement across an intervening phrase, finite vs nonfinite (\"creates\" / \"creating\" / \"to create\" / \"created\"), possessives vs plurals (\"microbes\" / \"microbe's\" / \"microbes'\"), pronoun number.",
          levels: "Easy: subject next to the verb. Hard: a long phrase between subject and verb, or a dangling modifier where four choices rewrite the start of the main clause."),
        // Expression of Ideas
        r("Expression of Ideas", "Transitions", 1,
          stems: "\"Which choice completes the text with the most logical transition?\"",
          form: "35 to 70 words; the blank ______ opens a sentence.",
          choices: "four transitions with their comma (\"However,\", \"Similarly,\", \"For example,\", \"In other words,\") from different logic families: contrast, addition, cause and effect, example, sequence, restatement.",
          levels: "Easy: a clear contrast or example. Hard: close pairs (\"That said,\" / \"Nevertheless,\"; \"Thus,\" / \"Still,\")."),
        r("Expression of Ideas", "Rhetorical Synthesis", 1.5,
          stems: "\"The student wants to [goal: emphasize a similarity / introduce X to an audience unfamiliar with Y / present the study and its findings]. Which choice most effectively uses relevant information from the notes to accomplish this goal?\"",
          form: "the line \"While researching a topic, a student has taken the following notes:\" then 5 or 6 notes, each on its own line starting \"• \" (40 to 100 words of notes).",
          choices: "one sentence each, 15 to 25 words, every one accurate to the notes; only the key meets the goal. Wrong ones meet a different goal.",
          levels: "Easy: the goal names one fact. Hard: the goal combines two conditions (a contrast for a specific audience)."),

        // Math: Algebra
        m("Algebra", "Linear equations in one variable", spr: 0.33,
          stems: "equation on its own line, then \"What value of x is the solution to the given equation?\" or \"Which equation has the same solution as the given equation?\"; \"If [a]x − [b] = [c], what is the value of x − [d]?\"; context: a fixed fee for the first hours and a rate after, \"Which equation represents this situation?\"; \"How many solutions does the equation [a](x − [b]) = [c](x + [d]) have?\"; \"Which statement is the best interpretation of [k]x in this context?\"",
          choices: "wrong ones: the solution of x + a = b, x − a = b or x/a = b in place of ax = b; the value of x when the question asks for x − d; per-unit vs total in interpretations.",
          levels: "Easy: 1 or 2 steps, integer answers. Medium: distribution, a fraction key, a rate context. Hard: solve for a grouped expression such as (m − nx), constants that force infinitely many or no solutions (\"s and r are constants… infinitely many solutions… value of s?\")."),
        m("Algebra", "Linear functions", spr: 0.20,
          stems: "\"The function f is defined by f(x) = [m]x + [b]. What is the value of f([k])?\" or \"For what value of x does f(x) = [c]?\"; \"For the linear function g, the graph of y = g(x) in the xy-plane has a slope of [m] and passes through the point ([p], [q]). Which equation defines g?\"; two-rate contexts (\"…for the first [n] people and [r2] for each additional person. Which function f gives the total…\"); interpretation of slope or intercept; a table of x and f(x) → h(x) = f(x) + [k].",
          choices: "a 2×2 sign grid of slope and intercept; wrong ones use the given point's y as the intercept, give b when asked for a + b, use f instead of h, double-count the first unit.",
          levels: "Easy: evaluate or read. Medium: build f from a point and a slope or a table. Hard: \"f([c]x) = x − [d] for all values of x… f([p]) = [q]. What is c?\""),
        m("Algebra", "Linear equations in two variables", spr: 0.40,
          stems: "\"It takes [a] minutes per [item1] and [b] per [item2]… total [T]… Which equation represents this situation?\"; \"The equation [a]x + [b]y = [c] represents… What is the best interpretation of [b]?\"; \"A line in the xy-plane has a slope of [p/q] and passes through (0, [b]). Which equation represents this line?\"; \"What is the slope of the graph of …?\"; perpendicular slope from standard form; given an equation, which table of x and y values fits.",
          choices: "wrong ones: coefficients swapped, x + y = T with no rates, the wrong axis read, slope vs negative reciprocal.",
          levels: "Easy: read a slope or intercept. Medium: build the equation from a context. Hard: coordinates with constants ((k, …), (k + 7, …)), mixture equations, y = f(x) + k."),
        m("Algebra", "Systems of two linear equations in two variables", spr: 0.27,
          stems: "stacked system, then \"The solution to the given system of equations is (x, y). What is the value of y?\"; tickets or admission (two prices, total people, total cost) → the count of one group; \"Which system represents this situation?\"; \"One of the two equations in a system of linear equations is given. The system has no solution. Which equation could be the second equation?\"",
          choices: "wrong ones: the other variable, the stated difference as the answer, a reversed multiple (m = 4c), parallel vs identical lines, scaling only one side.",
          levels: "Easy: one equation is already x = [n]. Medium: elimination with a context. Hard: a constant r that gives no solution; solve for a grouped expression (\"the value of [k](x − [a])\").",
          notes: "Desmos solves these by the intersection; Hard items add a constant so graphing needs a slider."),
        m("Algebra", "Linear inequalities in one or two variables", spr: 0.13,
          stems: "\"Which inequality best represents this situation, where s is…?\"; \"…no more than [W]… each box weighs [b]. What is the maximum number of boxes?\"; \"Which point (x, y) is a solution to the given system of inequalities?\"; interpret a term [b]y.",
          choices: "2×2 grid of rates swapped × direction reversed; integer answers with the neighbouring integers as wrong ones; wrong ones also from rounding the wrong way, the unrounded quotient, not flipping the sign when dividing by a negative. Use \"at least\", \"at most\", \"no more than\", \"minimum\", \"maximum possible\".",
          levels: "Easy: translate one condition. Medium: a two-variable budget. Hard: a system with a constant, or the boundary's constant from a described graph."),
        // Advanced Math
        m("Advanced Math", "Nonlinear functions", spr: 0.13,
          stems: "\"The function g is defined by g(x) = √([a]x + [b]). What is the value of g([k])?\"; \"…the graph of y = g(x) is the result of shifting the graph of y = f(x) [up/down/left/right] [n] units. Which equation defines g?\"; growth: \"…each month [r]% greater than the previous month. Which equation gives c, m months after…?\"; interpret an x-intercept, vertex or minimum value; nth term of a geometric sequence.",
          choices: "wrong ones: 0.07 / 1.07 / 1.7 / 7 for a 7% rate; n vs n − 1; the wrong shift direction; x at the minimum vs the minimum value; a constant vs its reciprocal. \"Decreasing exponential / Decreasing linear / Increasing exponential / Increasing linear\" as a fixed set.",
          levels: "Easy: evaluate. Medium: build a growth model or a shift. Hard: a change of time unit ((1.06)^(m/12)), vertex form from a maximum height and landing time, Roman-numeral structure questions with a < b < 0.",
          notes: "Desmos reads a vertex, a minimum or a zero."),
        m("Advanced Math", "Nonlinear equations in one variable and systems of equations in two variables", spr: 0.13,
          stems: "\"|x + [a]| = [b]. What is the positive solution to the given equation?\"; \"How many distinct real solutions does the given equation have?\"; \"What is one of the solutions to the given equation?\"; \"The given equation relates the positive numbers b, c, and f. Which equation correctly expresses c in terms of b and f?\"; a line and a parabola stacked → an ordered pair or a possible x.",
          choices: "wrong ones: a root with its sign flipped, the zero factor missed, the vertex instead of the intersection, y instead of x, inverse operations reversed in a literal equation.",
          levels: "Easy: a factored quadratic. Medium: a radical or rational equation. Hard: \"y = [k]; y = x² + [b]x + a… exactly one distinct real solution. What is a?\" (the discriminant); \"Which quadratic equation has no real solutions?\"; the sum or product of the solutions in terms of constants.",
          notes: "Desmos counts real solutions and reads intersections."),
        m("Advanced Math", "Equivalent expressions", spr: 0.27,
          stems: "\"Which expression is equivalent to [polynomial]?\" (like terms, a common factor, subtracting polynomials, a product of binomials, a sum of rational expressions); \"[expr] is equivalent to r·y^[n]([a]y − [b]), where r is a constant. What is the value of r?\"; \"(px + q)(rx + s) = ax² + bx + c… What is the value of b?\"",
          choices: "wrong ones: exponents added instead of kept, a sign error subtracting a polynomial, coefficients multiplied instead of added, a common factor only partly removed.",
          levels: "Easy: one operation. Medium: two products or a subtraction with negatives. Hard: rational expressions, \"One of the factors of [cubic] is x + b… the smallest possible value of b\", three-digit coefficients.",
          notes: "No figures."),
        // Problem-Solving and Data Analysis
        m("Problem-Solving and Data Analysis", "Ratios, rates, proportional relationships, and units", spr: 0.40,
          stems: "\"How many [unit B] are equivalent to [n] [unit A]? (1 [A] = [k] [B])\"; \"[A machine] does [a] in [t] minutes. At this rate, how many minutes will it take to do [b]?\"; \"The ratio of a to b is equivalent to [p] to [q]. What is the value of a when b = [n]?\"; density or a unit rate.",
          choices: "wrong ones: multiplying instead of dividing, converting linear instead of square units, adding instead of using the ratio, converting only one unit.",
          levels: "Easy: one conversion. Medium: a rate in a context; grid-in keys often 4 or 5 digits. Hard: squared units or two unit changes (\"…square feet per hour… in square meters per minute? (Use 1 meter = 3.28 feet.)\"), long science contexts.",
          notes: "No Desmos benefit."),
        m("Problem-Solving and Data Analysis", "Percentages", spr: 0.50,
          stems: "\"What percentage of [a] is [b]?\"; \"[p]% of the [N] [items] are [X]. How many are [X]?\"; \"[x] is [p]% of h. Which expression represents x in terms of h?\"; reverse and change: \"[p]% are faulty; [n] are faulty. How many in total?\", \"[p]% greater than last year\".",
          choices: "wrong ones: the complement, a decimal shift (89h, 8.9h, 0.089h), the wrong base, the percent number used as a count, 320% greater taken as ×3.2.",
          levels: "Easy: one percent of a number. Medium: a reverse percent or a percent change. Hard: chains (\"a is [p]% less than b; b is [q]% greater than [n]\"), changes of 100% or more, rounding to the nearest whole number."),
        m("Problem-Solving and Data Analysis", "One-variable data: Distributions and measures of center and spread", spr: 0.27,
          stems: "a data list on its own line, then the median, mean or range; a frequency table (Data value | Frequency) → maximum, mean or median; \"Which statement best compares the standard deviations…?\"; \"[value] was recorded in error and is removed… How do the medians compare?\"; \"Which must be less for F than for G? I. mean II. median\"; a weighted mean of two groups.",
          choices: "comparison choices \"less / greater / equal / There is not enough information…\"; wrong ones: the minimum instead of the median, the median of the unsorted list, a sum instead of a difference, a frequency instead of a value, an unweighted average.",
          levels: "Easy: a mean or median from a short list. Medium: a frequency table. Hard: an outlier's effect, standard deviation, weighted means.",
          notes: "Desmos is no help with these statistics concepts."),
        m("Problem-Solving and Data Analysis", "Two-variable data: Models and scatterplots", spr: 0.15,
          stems: "\"The scatterplot shows the relationship between two variables, x and y. A line of best fit is also shown. Which is closest to the slope of the line of best fit?\"; the predicted value at x = [k]; \"For how many of the [n] data points does the line predict a greater y-value than the actual?\"; \"Which equation is the most appropriate linear model?\"; \"What type of function best models…?\"",
          choices: "wrong ones: the intercept read as the slope, the wrong sign of the slope, the measured value instead of the predicted one, linear vs exponential.",
          levels: "Easy: read one prediction. Medium: interpret the slope in context. Hard: y = a(b)^x and \"closest to b\", y-values scaled by [k] → the new line, the average rate of change between two points.",
          notes: "Give the line of best fit by its equation and list the data points as a table, since no graph can be shown."),
        m("Problem-Solving and Data Analysis", "Probability and conditional probability", spr: 0.33,
          stems: "\"A [container] holds [N] [items], of which [n] are [X]. If one is selected at random, what is the probability that…?\"; a two-way table with Totals; \"neither [A] nor [B]\"; conditional: \"…what is the probability of selecting [row], given that [column condition]?\" (the condition often spans several columns: \"at least [n] years\"). A grid-in ends \"(Express your answer as a decimal or fraction, not as a percent.)\"",
          choices: "wrong ones: the complement, the grand total as the denominator, the reversed conditional, one column only, unreduced fractions kept as choices.",
          levels: "Easy: one count over a total. Medium: a two-way table. Hard: a condition across several columns or groups."),
        m("Problem-Solving and Data Analysis", "Inference from sample statistics and margin of error", spr: 0,
          stems: "\"Based on the sample, it is estimated that [parameter] is [e], with an associated margin of error of [m]. Which of the following is the most appropriate conclusion…?\" (key: \"It is plausible that [parameter] is between [e − m] and [e + m].\"); scale a random sample to the population; a plausible total from a percent ± margin; the margin from an interval (half its width).",
          choices: "wrong ones: \"exactly [e]\", values outside the interval, every individual value in the interval, sample-only counts, the complement count.",
          levels: "Medium: read the interval. Hard: doubling the sample size → \"less than [m]\", a projected vote difference."),
        m("Problem-Solving and Data Analysis", "Evaluating statistical claims: Observational studies and experiments", spr: 0,
          stems: "\"…selected [n] [units] at random from [population]… randomly assigned to two groups… What is the largest group to which the results can be generalized?\" or \"Which conclusion is appropriate?\"; 80 to 110 words, sometimes with a two-way table that shows only part of the sample.",
          choices: "full sentences or population names. Cause and effect needs random assignment; a generalization covers only the population sampled. Wrong ones: the sample only, a subset shown in the table, a broader population, a population with the wrong attribute.",
          levels: "Mostly Medium and Hard; Hard adds a table or a subset."),
        // Geometry and Trigonometry
        m("Geometry and Trigonometry", "Area and volume", spr: 0.20,
          stems: "\"A rectangle has an area of [A] square [units] and a length of [l] [units]. What is the width, in [units], of the rectangle?\"; \"A right circular cylinder has a base diameter of [d]… and a height of [h]. What is the volume, in cubic [units]?\" (choices in π); a prism's height from its volume. Formulas come from the reference sheet and are never stated in the stem.",
          choices: "wrong ones: the diameter used as the radius, the perimeter, face area or surface area instead of the volume, the circumference for the area, a linear factor applied to an area, a missing ½.",
          levels: "Easy: one formula. Medium: a composite shape or a missing dimension. Hard: scale factors (\"each side is [k] times as long… the area is n times\"), similar figures from their areas, a cylinder with radius × a and height × b."),
        m("Geometry and Trigonometry", "Lines, angles, and triangles", spr: 0.20,
          stems: "triangle angle sum; parallel lines m and n cut by transversal t with angle measures x° and w°: \"What is the value of w?\"; angles given as [a]k + [b] and [c]k − [d]; vertical angles; similar or congruent triangles with the correspondence stated; \"Which additional piece of information is sufficient to determine…?\"",
          choices: "wrong ones: the supplement instead of the equal angle, the complement, 90 − instead of 180 −, the wrong corresponding side, an angle scaled by a dilation factor, similar vs congruent.",
          levels: "Easy: one angle fact. Medium: angles given as expressions in k. Hard: overlapping triangles, isosceles sides, bisected angles, similar triangles through a shared vertex.",
          notes: "Describe the figure fully in words, as College Board does when a figure is not drawn to scale."),
        m("Geometry and Trigonometry", "Right triangles and trigonometry", spr: 0.27,
          stems: "a right triangle described in words → \"What is the value of sin x°?\" or \"Which equation shows the relationship between the side lengths?\"; similar right triangles share a trig value; the Pythagorean theorem with decimals or radicals; special right triangles (an equilateral triangle's height k√3, an isosceles right triangle's perimeter). Use \"sin x°\" for labeled degree measures and \"sin A\" for vertex angles.",
          choices: "wrong ones: sin, cos and tan confused, the reciprocal ratio, a + b or √(a + b) instead of √(a² + b²), a leg vs the perimeter, a squared length.",
          levels: "Easy: one ratio from three given sides. Medium: a missing side, then a ratio. Hard: \"cos Z = [a]/c. What is c?\", fraction grid-ins from a radical side, radians."),
        m("Geometry and Trigonometry", "Circles", spr: 0.45,
          stems: "\"(x − h)² + (y − k)² = [r²]. In the xy-plane, the graph of the given equation is a circle. What is the length of the circle's radius?\"; \"The point ([a], c) lies on this circle. What is a possible value of c?\"; a shifted or rescaled circle → the new equation or the constant k; arc lengths (minor + major = circumference), central angle = arc measure; \"What is the value of cos([n]π/[d])?\"; radians to degrees.",
          choices: "wrong ones: r² for r, a center coordinate as the radius, a shift sign reversed, a doubled radius taken as k doubled, sin/cos confusions, the difference of two arcs.",
          levels: "Easy: radius from the equation. Medium: arc length or sector. Hard: radians and the unit circle, completing the square for the center and radius.",
          notes: "Desmos shows a circle's center and radius."),
    ]
}
