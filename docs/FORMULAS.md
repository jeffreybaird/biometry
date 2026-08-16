# The formulas, explained

This document explains every formula this library computes and every variable
those formulas use. It assumes no medical background. Every constant quoted
here is transcribed in a file under `data/`, with a citation to the paper it
came from; this document explains those numbers but is not the source of them.

- [The measurements](#the-measurements)
- [The other terms you will meet](#the-other-terms-you-will-meet)
- [Step 1 — estimating the weight](#step-1--estimating-the-weight)
  - [The Hadlock 1985 weight formulas](#the-hadlock-1985-weight-formulas)
  - [The INTERGROWTH-21st weight formula](#the-intergrowth-21st-weight-formula)
- [Step 2 — placing the weight on a growth chart](#step-2--placing-the-weight-on-a-growth-chart)
  - [Hadlock 1991](#hadlock-1991--an-equation-chart)
  - [INTERGROWTH-21st](#intergrowth-21st--an-equation-chart-with-three-dials)
  - [NICHD](#nichd--a-table-chart-with-four-race-ethnicity-charts)
  - [WHO](#who--a-table-chart-with-sex-specific-charts)
- [Why each chart is tied to one weight formula](#why-each-chart-is-tied-to-one-weight-formula)
- [Dating a pregnancy](#dating-a-pregnancy)
- [Redating — the ACOG thresholds](#redating--the-acog-thresholds)

---

## The measurements

Everything starts with four measurements taken during an ultrasound scan.
Each is a length or a circumference, measured on the screen in millimetres.
The published formulas want centimetres, so the library converts once, in one
place.

| Abbreviation | Full name | What is actually measured |
|---|---|---|
| BPD | Biparietal diameter | The widest side-to-side span of the fetal skull. |
| HC | Head circumference | The distance around the outer perimeter of the skull. |
| AC | Abdominal circumference | The distance around the outer border of the fetal abdomen. |
| FL | Femur length | The length of the thigh bone's shaft, excluding the cartilage cap at its end. |

One more measurement appears in dating (not in weight estimation):

| Abbreviation | Full name | What is actually measured |
|---|---|---|
| CRL | Crown–rump length | The length from the top of the head to the bottom of the buttocks, used early in pregnancy. |

## The other terms you will meet

**Gestational age (GA).** How far along the pregnancy is, counted from the
first day of the mother's last menstrual period — *not* from conception,
which happens about two weeks later. It is written as weeks and days:
`32w0d` means exactly 32 weeks. Different growth standards want gestational
age in different numeric forms, and the library converts deliberately:

- *completed weeks* — whole weeks only, rounding down. 32 weeks and 6 days is
  still "week 32". The NICHD and WHO tables are published this way.
- *exact decimal weeks* — 30 weeks and 3 days becomes 30 + 3⁄7 ≈ 30.428571.
  The INTERGROWTH-21st equations are evaluated this way.
- *decimal weeks to the nearest tenth* — 39 weeks 3 days becomes 39.4. The
  Hadlock 1991 paper codes its ages this way, so this library does too.

**Estimated fetal weight (EFW).** The weight, in grams, that a formula
predicts from the measurements above. It is an estimate: the best formulas
carry a typical error of about 7–8% of the true weight.

**Percentile (also called a centile).** A rank against a comparison group.
"The 40th percentile" means the estimated weight is heavier than 40% of the
fetuses in that standard's reference population at the same gestational age,
and lighter than 60%. A percentile is *not* a verdict — this library reports
the number and its source and deliberately never attaches a label such as
"small" or "abnormal" to it.

**Standard deviation (SD).** A measure of spread. In a bell-curve (normal)
distribution, about 68% of values fall within one standard deviation of the
average and about 95% within two. Two of the growth standards describe their
spread this way.

**Z-score.** How many standard deviations a value sits from the median.
A Z-score of 0 is exactly the median; +1 is one standard deviation above.
A Z-score converts to a percentile through the normal distribution's
cumulative curve (for example, Z = 0 is the 50th percentile).

**Logarithms.** Several formulas predict the *logarithm* of the weight rather
than the weight itself, because fetal weight grows multiplicatively —
each week multiplies the weight rather than adding a fixed amount, and
logarithms turn multiplication into addition, which regression handles well.
Two kinds appear: `log10` (base-10: `log10(1000) = 3`) and `ln` or `log`
(natural log, base e ≈ 2.718). Each formula below says which it uses; undoing
a `log10` means raising 10 to the power of the result, and undoing a natural
log means raising e to it.

---

## Step 1 — estimating the weight

You cannot weigh a fetus. What you can do is measure it on an ultrasound
screen and put those measurements into a regression formula fitted on
pregnancies where the baby was born (and could be weighed) shortly after the
scan. This library carries two families of weight formulas.

### The Hadlock 1985 weight formulas

*Source: Hadlock et al., "Estimation of fetal weight with the use of head,
body, and femur measurements", American Journal of Obstetrics and Gynecology,
1985. Fitted on 276 pregnancies. Transcribed in `data/hadlock_1985.yml`.*

All four formulas take measurements in **centimetres** and produce `log10` of
the weight in **grams**. To get grams, raise 10 to the result. Each formula's
"standard deviation" figure is its typical prediction error as a percentage
of the true weight.

**Three-parameter formula (`hadlock_hc_ac_fl`)** — head circumference,
abdominal circumference, femur length. The authors' recommended general-use
model, and the one the NICHD and WHO growth charts were built on:

```
log10(weight) = 1.326 − 0.00326·AC·FL + 0.0107·HC + 0.0438·AC + 0.158·FL
```

Reading it term by term: start from a baseline of 1.326; each centimetre of
head circumference adds 0.0107 to the log-weight, each centimetre of
abdominal circumference adds 0.0438, each centimetre of femur adds 0.158, and
the `AC·FL` product term subtracts a small correction so that a fetus large
in both body and femur is not double-counted. Prediction error: 7.5% (one
standard deviation).

**Four-parameter formula (`hadlock_bpd_hc_ac_fl`)** — adds the biparietal
diameter. The formula the Hadlock 1991 growth chart was built on:

```
log10(weight) = 1.3596 − 0.00386·AC·FL + 0.0064·HC + 0.00061·BPD·AC
              + 0.0424·AC + 0.174·FL
```

Prediction error: 7.4%.

Two further Hadlock formulas are transcribed and available (`hadlock_ac_fl`,
using only abdomen and femur, error 8.0%; and `hadlock_bpd_ac_fl`, using
skull width, abdomen and femur, error 7.5%), but no growth chart in this
project pairs with them:

```
log10(weight) = 1.304 + 0.05281·AC + 0.1938·FL − 0.004·AC·FL
log10(weight) = 1.335 − 0.0034·AC·FL + 0.0316·BPD + 0.0457·AC + 0.1623·FL
```

### The INTERGROWTH-21st weight formula

*Source: Stirnemann et al., "International estimated fetal weight standards
of the INTERGROWTH-21st Project", Ultrasound in Obstetrics & Gynecology,
2017. Transcribed in `data/intergrowth21.yml`.*

INTERGROWTH-21st published its own formula rather than reusing Hadlock's. It
uses only two measurements — abdominal circumference and head circumference —
and the natural logarithm. Femur length was tested and deliberately left out;
the authors judged it would likely worsen the prediction. Measurements in
centimetres, and note the divisions by 100, which convert to metres:

```
log(weight) = 5.084820
            − 54.06633 · (AC/100)³
            − 95.80076 · (AC/100)³ · log(AC/100)
            + 3.136370 · (HC/100)
```

To get grams, raise e to the result. The paper's own worked example — an
abdominal circumference of 26 cm and a head circumference of 29 cm — gives
`log(weight) = 7.312292`, which is 1,499 grams, and this library reproduces
it exactly. Typical prediction error: about 7.6%; 80% of predictions fall
within 11% of the true weight, and 95% within 18%.

---

## Step 2 — placing the weight on a growth chart

A weight alone means little — 1,800 grams is heavy for 30 weeks and light for
36. A *growth standard* answers "compared to what?": it describes, for each
gestational age, how the weights of a reference population are distributed,
so a given weight can be placed at a percentile.

The four standards this library carries answer that question from different
populations and with different philosophies, which is why they disagree —
and that disagreement is the library's output, not a nuisance. Two
distinctions recur:

- **Equation charts vs table charts.** Hadlock 1991 and INTERGROWTH-21st
  publish formulas, so any percentile at any age in range is computable.
  NICHD and WHO publish tables — a grid of weights at fixed percentiles for
  each completed week — so the library looks up the bracketing columns and
  draws a straight line between them (linear interpolation in weight). When a
  weight falls outside the outermost printed column, the library reports a
  bound — "above the 95th" — and never extrapolates past what the source
  printed.
- **Prescriptive vs reference.** A *prescriptive* standard (INTERGROWTH-21st,
  NICHD) recruited only healthy, low-risk pregnancies and describes how
  fetuses grow under good conditions. A *reference* (Hadlock 1991, WHO)
  describes a population as it actually presented, complications included.
  A 10th percentile therefore does not mean the same thing on the two kinds
  of chart, and the library names the kind in every report.

### Hadlock 1991 — an equation chart

*Source: Hadlock, Harrist & Martinez-Poyer, "In utero analysis of fetal
growth: a sonographic weight standard", Radiology, 1991. 392 pregnancies,
predominantly middle-class white women at a single centre — the narrow base
the later NICHD study was a response to. Transcribed in
`data/hadlock_1991.yml`.*

The median (50th-percentile) weight follows one equation of gestational age,
here called MA (menstrual age, the paper's term for gestational age), in
decimal weeks to the nearest tenth:

```
ln(median weight in grams) = 0.578 + 0.332·MA − 0.00354·MA²
```

The spread is a fixed percentage of the median: one standard deviation is
some percentage `s` of the median weight, and any percentile is

```
weight at percentile α = median · (1 + Zα · s/100)
```

where `Zα` is the Z-score for that percentile (for the 3rd percentile,
Zα ≈ −1.88). To place a weight, the library computes the median at that age,
asks how many standard deviations the weight sits from it, and converts to a
percentile. Valid range: 10–40 weeks.

**What is `s`? The paper gives two answers, and the library reports both.**
The abstract states 12.7%. The paper's own Table 1 centiles are exactly the
median multiplied by {0.750, 0.830, 1.170, 1.250} at every single week,
which implies 13.3%. No erratum has ever been issued, and two independent
research groups who recalculated the table in 2025–26 (Roberts et al.;
Gleason et al., both in the American Journal of Obstetrics and Gynecology)
favour the abstract's figure — Roberts reporting that the table method would
have underdiagnosed fetal growth restriction in 5.1% of patients relative to
the equation method. Because the choice shifts results by about one
percentile near common decision thresholds, every report carries two Hadlock
1991 rows: **`(equation)`**, using 12.7%, the default; and **`(table)`**,
using 13.3%, which reproduces the printed Table 1 exactly. Both figures live
in `data/hadlock_1991.yml` under `variants`, nowhere else, so a future
correction is a one-file data change.

### INTERGROWTH-21st — an equation chart with three dials

*Source: same Stirnemann et al. 2017 paper as the formula. A prescriptive
standard built from healthy pregnancies in eight countries; no sex or
ethnicity stratification, by design. Transcribed in `data/intergrowth21.yml`.*

Instead of a single spread figure, INTERGROWTH-21st describes the weight
distribution at each age with three parameters — a method called **LMS**,
for **L**ambda (skewness: how lopsided the distribution is), **M**u (the
median), and **S**igma (the spread). Each is a smooth function of
gestational age GA in exact decimal weeks:

```
L(GA) = −4.257629 − 2162.234·GA⁻² + 0.0002301829·GA³
M(GA) =  4.956737 + 0.0005019687·GA³ − 0.0001227065·GA³·log(GA)
S(GA) = 10⁻⁴ · (−6.997171 + 0.057559·GA³ − 0.01493946·GA³·log(GA))
```

These apply to `Y = log(estimated weight)` — the natural log again. A weight
becomes a Z-score via

```
Z = ((Y/M)^L − 1) / (S·L)        (or log(Y/M)/S in the special case L = 0)
```

and the Z-score becomes a percentile through the normal curve. Valid range:
22–40 weeks. The library evaluates these at the exact age — 30 weeks 3 days
is 30.428571, not 30.

### NICHD — a table chart with four race/ethnicity charts

*Source: Buck Louis et al., "Racial/ethnic standards for fetal growth: the
NICHD Fetal Growth Studies", American Journal of Obstetrics and Gynecology,
2015. NICHD is the United States National Institute of Child Health and
Human Development. 1,737 healthy low-risk pregnancies at 12 United States
sites. Manifest in `data/nichd.yml`; the table itself in
`data/percentiles/nichd.csv`.*

No equation — a printed table: for each completed week and each of four
self-reported race/ethnicity groups (white, black, Hispanic, Asian or
Pacific Islander), the weights at the 3rd, 5th, 10th, 50th, 90th, 95th and
97th percentiles. The paper's headline finding is that the four charts
differ enough to matter, so:

- the library never infers or defaults the group. Ask for a percentile
  without naming one and it returns all four readings, because the spread
  between them *is* the answer;
- the published table covers weeks 10–40, but the curves were only fitted
  from week 15, so the library refuses to read weeks 10–14 rather than
  report a number resting on essentially no data.

### WHO — a table chart with sex-specific charts

*Source: Kiserud et al., "The World Health Organization Fetal Growth
Charts", PLoS Medicine, 2017. WHO is the World Health Organization. 1,362
pregnancies across ten countries. Manifest in `data/who.yml`; tables in
`data/percentiles/who.csv`.*

Also a printed table, per completed week from 14 to 40, at up to nine
percentile columns (2.5th through 97.5th), in three variants: combined,
female and male. Male fetuses run 3.5–4.5% heavier, so naming the sex picks
a chart; unknown sex reads the combined one. WHO deliberately built a
*reference*, keeping complicated pregnancies in the data — its 10th
percentile is not comparable to a prescriptive chart's 10th. The
sex-specific charts print fewer columns at some weeks (only the 5th–95th),
which narrows the range in which a percentile can be read before the
"above/below the outermost column" bound applies.

---

## Why each chart is tied to one weight formula

Each growth standard built its curves from weights computed by one specific
formula. Compare a weight from a *different* formula against those curves and
the systematic differences between formulas masquerade as growth findings.
So the pairing is enforced:

| Growth chart | Weight formula it was built on |
|---|---|
| Hadlock 1991 (both variants) | Hadlock four-parameter (BPD + HC + AC + FL) |
| NICHD | Hadlock three-parameter (HC + AC + FL) |
| WHO | Hadlock three-parameter (HC + AC + FL) |
| INTERGROWTH-21st | INTERGROWTH's own formula (AC + HC) |

A report therefore carries up to three *different* weights across the four
charts — that is correct, not a bug. Ask a chart to read a weight from the
wrong formula and the library refuses with `formula_chart_mismatch`.

---

## Dating a pregnancy

Gestational age has to come from somewhere. The library implements two
derivations, and reports every one it can compute rather than silently
choosing.

**From the last menstrual period (LMP) — Naegele's rule.** Pregnancy is
conventionally 280 days (40 weeks) from the first day of the last menstrual
period, assuming a 28-day cycle. A longer or shorter cycle shifts ovulation,
so the correction is added on:

```
estimated due date (EDD) = LMP + 280 days + (cycle length − 28)
gestational age today    = today − (EDD − 280 days)
```

**From an embryo transfer (in-vitro fertilisation).** Conception is counted
as if it happened two weeks into a notional cycle, so a pregnancy is already
14 days old on its conception day:

```
gestational age on the transfer day = 14 days + the embryo's age in days
```

A day-5 blastocyst (an embryo transferred five days after fertilisation)
means the pregnancy is 2 weeks 5 days old at transfer. The embryo's age must
be supplied — guessing between day 3 and day 5 is a silent two-day error.

---

## Redating — the ACOG thresholds

*Source: ACOG (the American College of Obstetricians and Gynecologists)
Committee Opinion No. 700, "Methods for Estimating the Due Date", 2017.
Transcribed in `data/acog_redating.yml`.*

When an ultrasound implies a different due date than the one already
established, ACOG's guidance says: change the established date only when the
disagreement exceeds a threshold, and the threshold grows with gestational
age, because ultrasound dating gets less precise as pregnancy advances.
The thresholds are exclusive — redate only when the discrepancy is *strictly
greater* than the threshold:

| Established gestational age | Measured by | Redate when the dates differ by more than |
|---|---|---|
| up to 8w6d | crown–rump length | 5 days |
| 9w0d – 13w6d | crown–rump length | 7 days |
| 14w0d – 15w6d | biometry (BPD, HC, AC, FL) | 7 days |
| 16w0d – 21w6d | biometry | 10 days |
| 22w0d – 27w6d | biometry | 14 days |
| 28w0d onward | biometry | 21 days |

Two refinements the library reports rather than deciding:

- In the 22–27 week band, a discrepancy of 10–14 days falls in a
  *discretionary zone* — redating may be appropriate depending on clinical
  judgement, so the service reports the zone rather than a bare yes or no.
- From 28 weeks, a caveat is attached: third-trimester dating carries error
  on the order of ±21–30 days, and redating a small fetus late risks masking
  growth restriction.

Two rules override the arithmetic entirely: a pregnancy dated by in-vitro
fertilisation is never redated by ultrasound (the conception date is known
exactly), and an established due date is never mutated — the service returns
a recommendation with its reasoning, and the caller decides.
