import Foundation

/// SAT math words with a plain-English meaning (and the Japanese term). "english|日本語|meaning".
enum Glossary {
    static let all: [Vocab] = raw.split(separator: "\n").compactMap { line in
        let p = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        return p.count == 3 ? Vocab(en: p[0], ja: p[1], note: p[2]) : nil
    }

    /// English or Japanese, prefix matches first.
    static func search(_ q: String, in list: [Vocab] = all) -> [Vocab] {
        let q = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let hits = list.filter { $0.en.lowercased().contains(q) || $0.ja.contains(q) || $0.note.contains(q) }
        return hits.sorted { a, b in
            let pa = a.en.lowercased().hasPrefix(q) || a.ja.hasPrefix(q), pb = b.en.lowercased().hasPrefix(q) || b.ja.hasPrefix(q)
            return pa != pb ? pa : a.en.count < b.en.count
        }
    }

    private static let raw = """
    value of|〜の値|The result you get after plugging numbers into an expression
    expression|式|Math terms joined by plus or minus, with no equals sign
    equation|方程式|Two expressions set equal to each other
    inequality|不等式|Two expressions compared with less than or greater than
    solution|解|A value that makes an equation or inequality true
    solve for x|x について解く|Find the value of x that makes the equation true
    in terms of|〜を用いて表す|Written using only the listed variables
    coefficient|係数|The number multiplying a variable, like 3 in 3x
    constant|定数|A number that does not change, like 5 in x + 5
    term|項|One piece of an expression separated by plus or minus signs
    like terms|同類項|Terms with the same variables raised to the same powers
    variable|変数|A letter that stands for an unknown or changing number
    integer|整数|A whole number, positive, negative, or zero
    positive integer|正の整数|A whole number greater than zero: 1, 2, 3
    nonnegative|0 以上の|Zero or any positive number
    whole number|0 以上の整数|Zero and the positive counting numbers: 0, 1, 2
    real number|実数|Any number on the number line, including fractions and roots
    rational number|有理数|A number that can be written as a fraction of integers
    irrational number|無理数|A number that cannot be written as a simple fraction, like pi
    prime number|素数|A whole number greater than 1 with only two factors, 1 and itself
    factor|因数・約数|A number that divides another evenly; also to split into products
    multiple|倍数|A number you get by multiplying another number by an integer
    divisible by|〜で割り切れる|Divides into evenly with no remainder
    remainder|余り|The amount left over after division
    quotient|商|The result of dividing one number by another
    product|積|The result of multiplying numbers
    sum|和|The result of adding numbers
    difference|差|The result of subtracting one number from another
    reciprocal|逆数|The number you multiply by to get 1, like 1/2 for 2
    absolute value|絶対値|How far a number is from zero, always positive or zero
    square root|平方根|A number that multiplied by itself gives the original number
    exponent|指数|The small raised number showing how many times to multiply
    base|底・底辺|The number being raised to a power, or a side a shape rests on
    power|累乗|A number raised to an exponent, like 2 to the power of 3
    radical|根号・累乗根|An expression with a root sign, like the square root sign
    numerator|分子|The top number of a fraction
    denominator|分母|The bottom number of a fraction
    simplify|簡単にする|Rewrite an expression in its shortest, cleanest form
    equivalent|同値な・等しい|Equal in value, even if written differently
    evaluate|値を求める|Find the numeric value of an expression
    substitute|代入する|Replace a variable with a number or expression
    isolate|（x を）片側だけにする|Get a variable alone on one side of an equation
    distribute|分配する|Multiply a number across every term inside parentheses
    factor completely|完全に因数分解する|Factor until no more factoring is possible
    linear|一次の|Having a straight-line graph; degree one
    linear function|一次関数|A function whose graph is a straight line
    quadratic|二次の|Having the variable squared as its highest power
    quadratic function|二次関数|A function with x squared as its highest power, graphed as a parabola
    polynomial|多項式|An expression made of terms with whole-number powers of variables
    exponential|指数関数的な|Growing or shrinking by a fixed multiplier each step
    exponential growth|指数関数的増加|Quantity that multiplies by the same factor over equal periods
    exponential decay|指数関数的減少|Quantity that shrinks by the same factor over equal periods
    function|関数|A rule that gives exactly one output for each input
    input / output|入力 / 出力|The x value you put in, and the f(x) value you get out
    domain|定義域|All the input values a function is allowed to take
    range|値域・範囲|All possible output values. In statistics, max minus min
    slope|傾き|How steep a line is: rise over run
    rate of change|変化の割合|How much one quantity changes per unit of another, like slope
    y-intercept|y 切片|The point where a graph crosses the y-axis
    x-intercept|x 切片|The point where a graph crosses the x-axis
    zero (of a function)|零点・解|An input x that makes the function equal zero
    root|解・根|A solution of an equation; a value that makes it zero
    vertex|頂点|The highest or lowest point of a parabola
    axis of symmetry|対称軸|The vertical line that splits a parabola into mirror halves
    parabola|放物線|The U-shaped graph of a quadratic function
    system of equations|連立方程式|Two or more equations solved together for shared values
    no solution|解なし|The lines never cross, so no values work
    infinitely many solutions|解が無数にある|The equations are the same line, so every point works
    parallel|平行|Lines with the same slope that never meet
    perpendicular|垂直|Lines that cross at a right angle; slopes multiply to -1
    proportional to|〜に比例する|Changes by a constant ratio with another quantity
    inversely proportional|反比例する|One value goes up as the other goes down, product stays constant
    directly proportional|正比例する|One value increases at a steady ratio with the other
    ratio|比|A comparison of two quantities, like 2 to 3
    proportion|比例式・割合|Two equal ratios written as an equation
    rate|割合・速さ|A ratio comparing two different units, like miles per hour
    percent increase|増加率（%）|How much a value grows, as a percent of the original
    percent decrease|減少率（%）|How much a value shrinks, as a percent of the original
    percent of|〜の何%|A part of a whole, shown as a percent of it
    unit rate|単位あたりの量|A rate for exactly one unit, like price per item
    mean|平均（値）|The average: sum of values divided by how many there are
    median|中央値|The middle value when data is listed in order
    mode|最頻値|The value that appears most often in a data set
    standard deviation|標準偏差|How spread out data is from the mean
    outlier|外れ値|A value far away from the rest of the data
    data set|データの集まり|A collection of numbers or observations to analyze
    frequency|度数|How many times a value or group appears
    scatterplot|散布図|A graph of points showing the relationship between two variables
    line of best fit|近似直線・回帰直線|A straight line that follows the trend of scattered points
    histogram|ヒストグラム|A bar graph showing how data falls into ranges
    box plot|箱ひげ図|A chart showing median, quartiles, and extremes of data
    sample|標本|A smaller group chosen to represent a larger group
    population|母集団|The whole group a study is about
    random sample|無作為標本|A sample where every member has an equal chance to be picked
    margin of error|誤差の範囲|How far a survey result might be from the true value
    probability|確率|The chance an event happens, from 0 to 1
    at least|少なくとも・〜以上|Equal to or greater than a given number
    at most|多くとも・〜以下|Equal to or less than a given number
    no more than|〜以下|Less than or equal to a given number
    no less than|〜以上|Greater than or equal to a given number
    exceeds|〜を超える|Is greater than a given number
    greater than or equal to|〜以上|Bigger than or the same as; the symbol is ≥
    less than|〜未満|Smaller than; the symbol is <
    respectively|それぞれ（順に）|In the same order as listed
    consecutive|連続する|Following one another in order, like 4, 5, 6
    triangle|三角形|A three-sided shape whose angles add up to 180 degrees
    right triangle|直角三角形|A triangle with one 90-degree angle
    isosceles triangle|二等辺三角形|A triangle with two equal sides and two equal angles
    equilateral triangle|正三角形|A triangle with three equal sides and angles
    hypotenuse|斜辺|The longest side, across from the right angle
    leg|（直角三角形の）直角をはさむ辺|A side of a right triangle that touches the right angle
    similar|相似な|Same shape, different size; angles match, sides are proportional
    congruent|合同な|Exactly the same size and shape
    angle|角|The space between two lines meeting at a point, in degrees
    acute angle|鋭角|An angle smaller than 90 degrees
    obtuse angle|鈍角|An angle bigger than 90 degrees but less than 180
    right angle|直角|An angle of exactly 90 degrees
    supplementary angles|和が 180° の角|Two angles that add up to 180 degrees
    complementary angles|和が 90° の角|Two angles that add up to 90 degrees
    vertical angles|対頂角|Opposite angles formed when two lines cross; they are equal
    adjacent|隣り合う|Next to each other, sharing a side
    perimeter|周の長さ|The total distance around the outside of a shape
    area|面積|The amount of flat space inside a shape
    volume|体積|The amount of space a 3D object fills
    surface area|表面積|The total area of all faces of a 3D object
    circumference|円周|The distance around a circle
    radius|半径|The distance from a circle's center to its edge
    diameter|直径|A line through a circle's center; twice the radius
    arc|弧|A part of the edge of a circle
    central angle|中心角|An angle with its vertex at a circle's center
    sector|おうぎ形|A slice of a circle bounded by two radii and an arc
    chord|弦|A line segment joining two points on a circle
    tangent|接線・正接（tan）|A line touching a circle at one point; also a trig ratio
    radian|ラジアン|An angle unit: the angle where arc length equals radius
    rectangle|長方形|A four-sided shape with four right angles
    square|正方形・2 乗|A rectangle with four equal sides; also a number times itself
    parallelogram|平行四辺形|A four-sided shape with two pairs of parallel sides
    trapezoid|台形|A four-sided shape with exactly one pair of parallel sides
    polygon|多角形|A closed shape made of straight line segments
    cube|立方体・3 乗|A 3D box with six equal square faces; also a number cubed
    rectangular prism|直方体|A 3D box with six rectangular faces
    cylinder|円柱|A 3D shape with two circular ends and a curved side
    cone|円錐|A 3D shape with a circle base that tapers to a point
    sphere|球|A perfectly round 3D ball
    pyramid|角錐|A 3D shape with a base and triangles meeting at a point
    sine / cosine|サイン / コサイン|Trig ratios of an angle in a right triangle
    xy-plane|xy 平面・座標平面|The flat grid made by the x and y axes
    coordinate|座標|A pair of numbers giving a point's position on a grid
    origin|原点|The point (0, 0) where the axes cross
    midpoint|中点|The point exactly halfway between two points
    distance|距離|How far apart two points are
    """
}
