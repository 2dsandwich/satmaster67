# Digital SAT Math: skill-level style guide

Deepens SAT-STYLE.md. Basis: 267 Question Bank Math items (~5 per skill × difficulty) plus the Framework. Placeholders in [ ]; percentages are sample estimates.

## Global rules
- **SPR:** 26% (E 9%, M 32%, H 36%). Keys: 72% integers (7% negative), 27% fraction/decimal. Max 5 characters (6 with "−"). List all accepted forms (`49/2, 24.5`; repeating: `2/43, .0465, .046, .047`). No %, units, π or √ in answers: ask "…is k√3 cm, where k is a constant. What is k?" Probability SPR ends "(Express your answer as a decimal or fraction, not as a percent.)" Rounding stated ("to the nearest whole number").
- **MC order:** numbers ascending (89%), sometimes descending (9%), never shuffled; π/√ values by size; fractions by numerator; pairs by x then y. Expression/equation choices are a 2×2 of two errors (coefficient × constant, < vs >, roles swapped), A/B sharing one feature; signs run (−,−) (−,+) (+,−) (+,+). Fixed sets: "Exactly one / Exactly two / Infinitely many / Zero"; "I only / II only / I and II / Neither I nor II". Text choices parallel, equal length.
- **Keys:** A 29%, B 27%, C 21%, D 23%; sorted choices put the key at A/D as often as B/C.
- **Notation:** 1,150 (not years); stem decimals 0.49; $950; 6%; "[n] centimeters (cm)" then "cm"; unit in question ("What is the area, in square meters, …"); conversions in parentheses at end "(1 [A] = [k] [B])", approximate "(Use 1 meter = 3.28 feet.)"; "where a, b, and c are constants", "k is a positive constant"; "for x > 0"; equations on their own lines, then "The given equation…"; "In the xy-plane, the graph of y = f(x)…"; "Which of the following is closest to…".
- **Distractors:** of the explained ones (half say only "conceptual or calculation errors"): ~45% another quantity from the problem (intermediate step, other variable, a given number); ~20% solution of a mis-built equation (wrong inverse operation, × for ÷); ~15% feature swaps (sign, coefficients, direction, at least/at most); rest reciprocal, complement, squared/unsquared, decimal shift.
- **Figures:** serif. xy-plane: grid, italic x/y at arrow ends, origin "O", round tick steps, axis titles with units. Geometry: capital vertices, x°, right-angle box, "Note: Figure not drawn to scale." under nearly all lines/angles and right-triangle figures. Tables: header row, Total row/column.
- **Desmos:** fast for explicit equations (intersections, zeros, solution counts, vertex, circle center/radius, point-in-inequality, table regression, equivalence by overlay). No help for interpretation, setup, figures, statistics, percents. Hard items add an unknown constant or condition (no solution, infinitely many) so graphing needs sliders.

## Algebra
**Linear equations in one variable** (SPR 33%; no figures; Desmos E/M only)
- Equation alone → "What value of x is the solution…?" / "Which equation has the same solution…?"; "If [a]x − [b] = [c], what is the value of x − [d]?"
- "[fee] for the first [n] hours and [r] per hour after… total [T]. Which equation represents this situation?"; interpret a term "[k]x".
- H: solve for a repeated binomial; "How many solutions…?"; "s and r are constants… infinitely many solutions… s?"
- Distractors: solution of x + a = b, x − a = b, x/a = b; x when asked x − d; per-unit vs total.
- E integer 1–2 steps · M distribute, fraction key, rate context · H structure, constants.

**Linear equations in two variables** (SPR 40%)
- "[a] minutes per [item1], [b] per [item2], total [T]… Which equation represents this situation?"; interpret coefficient vs term vs variable.
- "slope [p/q] through (0, [b])"; "slope [m], x-intercept ([h], 0): y-intercept?"; slope of y = [p/q]([a]x + [b]) + [c]x; perpendicular slope from standard form; equation → matching table; budget-line graph read.
- Distractors: swapped coefficients, x + y = T, wrong axis, negative reciprocal errors. H: points with constants (k, …), mixtures, y = f(x) + k.

**Linear functions** (SPR 20%; graph in ~15%)
- "f is defined by f(x) = [m]x + [b]. What is f([k])?" / "For what x does f(x) = [c]?"; "graph of the linear function f is shown, where y = f(x). Which equation defines f?"; "slope [m], passes through ([p], [q]). Which equation defines g?"
- "[r1] each for the first [n], [r2] each additional… which function f…, where n ≥ [n]?"; interpret intercept/slope; table → h(x) = f(x) + [k]; H "f([c]x) = x − [d] for all x".
- Distractors: 2×2 sign grid, given point's y as intercept, b for a + b, f for h, first unit double-counted.

**Systems of two linear equations** (SPR 27%; Desmos for numeric systems)
- Stacked system → "The solution… is (x, y). What is the value of y?" (E: one equation is x = [n]).
- Two prices, total people, total cost → one count; "[A] has [k] times as many… together [T]. Which system represents…?"
- "One of the two equations… is given. The system has [no / infinitely many / exactly one] solution(s). Which equation could be the second?"; H: constant r for no solution, elimination on grouped terms.
- Distractors: other variable, stated difference, reversed multiple, parallel vs same line.

**Linear inequalities** (SPR 13%)
- Translate ("at least, at most, no more than, under") with 2×2 choices; integer max/min ("maximum number of boxes"; distractors adjacent integers); point or table satisfying a system; dashed-boundary shaded graph → constant; interpret [b]y.
- Distractors: direction reversed, rounding wrong way, tax added to budget, sign not flipped.

## Advanced Math
**Equivalent expressions** (SPR 27%; no figures)
- "Which expression is equivalent to…?" (like terms, GCF, subtraction, binomial product, rational sum); "[expr] = r·y^[n](…) , r constant. r?"; "(px + q)(rx + s) = ax² + bx + c. b?"; f, g, h on separate lines, f·g − h.
- H: factor x + b of a cubic, smallest b; "(hx + k)(x + j), integer constants. Which must be an integer?"
- Distractors: exponents added (7x⁶), sign error subtracting, coefficients multiplied, partial GCF.

**Nonlinear equations and systems** (SPR 13%; Desmos strong unless constants)
- "|x + [a]| = [b]. Positive solution?"; "How many distinct real solutions…?"; "one of the solutions" (factored); "relates the positive numbers b, c, and f… c in terms of b and f?"; line + parabola (stacked or graphed).
- H: "y = [k]; y = x² + [b]x + a; exactly one real solution. a?"; which quadratic has no real solutions; sum/product of solutions with constants.
- Distractors: root sign flipped, zero factor missed, vertex instead of intersection, y for x.

**Nonlinear functions** (SPR 13%; graphs ~15%)
- "g(x) = √([a]x + [b]). g([k])?"; "graph of y = g(x) is the graph of y = f(x) shifted [up] [n] units. Which equation defines g?"; "[N] in [year], each month [r]% greater… c, m months after…, m ≤ [k]?"; interpret x-intercept/vertex/minimum; geometric sequence.
- H: years → months in the exponent; vertex form from max height and landing time; I/II structure with a < b < 0.
- Distractors: 0.07 / 1.07 / 1.7 / 7; n vs n − 1; shift direction; argmin vs minimum; reciprocal of a constant.

## Problem-Solving and Data Analysis
**Ratios, rates, proportions, units** (SPR 40%; no Desmos)
- "How many [B] are equivalent to [n] [A]? (1 [A] = [k] [B])"; "[a] in [t] minutes; at this rate…"; "ratio a to b = [p] to [q]; a when b = [n]?"; density/unit rate.
- H: squared units or two unit changes, 100-word science context, "rounded to the nearest tenth".
- Distractors: × vs ÷, linear instead of square conversion, add/subtract instead of ratio, one unit converted.

**Percentages** (SPR 50%)
- "What percentage of [a] is [b]?"; "[p]% of [N]…"; "[x] is [p]% of h. Expression?"; reverse ("[p]% are faulty; [n] faulty; total?"); "[p]% greater than".
- H: two-step chains, ≥100% changes, "[k] times… p%, nearest whole number".
- Distractors: complement, decimal shift (89h, 8.9h, 0.089h), wrong base, percent as count, "320% greater" → ×3.2.

**One-variable data** (SPR 27%; table or plot ~50%)
- Data list on its own line → median/mean/range; frequency table; dot plot/bar graph reading; histogram SD comparison; "same median as…" (list choices).
- H: remove/add an outlier and compare mean/median; "Which must be less…? I. mean II. median"; weighted mean of two groups. Comparison choices: less / greater / equal / not enough information.
- Distractors: min as median, unsorted median, sum for difference, frequency vs value, unweighted mean.

**Two-variable data** (SPR 15%; scatterplot nearly always)
- "The scatterplot shows… A line of best fit is also shown." → closest slope; predicted y at x = [k]; points above/below line; "most appropriate linear model" (y = a + bx choices or graph choices); "What type of function best models…?" (linear/exponential × increasing/decreasing).
- H: y = a(b)^x, closest b; y-values scaled by [k]; average rate of change between two points.
- Distractors: intercept as slope, wrong slope sign, measured vs predicted, linear vs exponential.

**Probability** (SPR 33%; two-way table ~1/3)
- "[N] items, [n] are [X]; selected at random, probability…?"; "neither [A] nor [B]"; given P(A), P(B) → count of C; "…given that [condition]" over several columns.
- Distractors: complement, grand total as denominator, reversed conditional, one column only; unreduced fractions (2/14, 7/7) allowed.

**Inference and margin of error** (MC only)
- "Based on the sample, it is estimated that [parameter] is [e], with an associated margin of error of [m]. …most appropriate conclusion?" Key: "It is plausible that… between [e − m] and [e + m]." Also: scale a random sample to the population; margin = half interval; H: larger sample → smaller margin; projected vote gap.
- Distractors: "exactly [e]", outside the interval, all individuals in the interval, sample-only counts.

**Evaluating statistical claims** (MC; 3 items, M/H, 80–110 words; weakly verified)
- "selected [n] at random from [population]… randomly assigned to two groups… largest population to which the results can be generalized?", often with a table of a subset. Causation needs random assignment; generalize only to the sampled population.
- Distractors: sample only, table subset, broader population, wrong attribute.

## Geometry and Trigonometry
**Area and volume** (SPR 20%; formulas never stated, they are on the reference sheet)
- "Area [A], length [l]: width, in [unit]?"; "cylinder, base diameter [d], height [h]: volume?" (π choices); prism height from volume. H: scale factor k → k², k³; similar figures from areas; triangle area from plotted points.
- Distractors: diameter as radius, perimeter/face/surface area for volume, circumference for area, missing ½, linear factor on area.

**Lines, angles, triangles** (SPR 20%; figure ~75%)
- Angle sum; m ∥ n cut by t, "value of w?" (M: angles [a]k + [b], [c]k − [d]); vertical angles; similar/congruent with stated correspondence; "additional information needed/sufficient". H: overlapping triangles, isosceles, bisectors.
- Distractors: supplement vs equal, complement, 90 − for 180 −, wrong corresponding side, angle scaled by dilation.

**Right triangles and trigonometry** (SPR 27%; figure ~55%)
- Labeled triangle → "value of sin x°?" / "relationship between the side lengths?"; similar right triangles share ratios; Pythagorean with decimals/radicals; special triangles (k√3). H: "cos Z = [a]/c. c?", fraction SPR from a radical side.
- Distractors: sin/cos/tan swapped, reciprocal, a + b or √(a + b), leg vs perimeter, squared side. "sin x°" for labeled degrees, "sin A" for vertices.

**Circles** (SPR 45%; Desmos for equations)
- "(x − h)² + (y − k)² = [r²]: radius?"; point ([a], c) on circle; "NOT a possible value of q"; shifted or rescaled circle; minor + major arc = circumference; arc measure + length → radius; "value of cos([n]π/[d])?"; radians → degrees.
- Distractors: r² for r, center coordinate as radius, shift sign reversed, doubled radius → doubled k, sin/cos/1/tan.
- E diameter → radius · M point on circle, arcs · H large radian angles, transformations.
