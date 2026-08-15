# frozen_string_literal: true

# Ruby port of FetalGPSR (dw1227/FetalGPSR, R/FetalGPS.R, built 2020-05-14),
# cross-checked against FetalGPSX's VBA (Sheet1.cls).
#
# Ported so oracle fixtures can be regenerated without an R toolchain, and so
# the port itself is reviewable in the same language as the library.
#
# Their conventions are preserved DELIBERATELY, including where we disagree:
#
#   * gestational age supplied in DAYS; biometry in MILLIMETRES
#   * the EFW formula is chosen by WHICH INPUTS ARE PRESENT, not by which chart
#     is being read:  BPD absent -> 3-parameter Hadlock, BPD present -> 4-param,
#     applied identically for every standard. Their own paper claims otherwise.
#   * the Hadlock chart uses sd = 0.127 * mu, the figure from that paper's
#     abstract. We use 0.133, back-calculated from its Table 1 centile ratios,
#     which reproduces the published table exactly. See FIXTURES.md tier 4.
#   * WHO and NICHD index by floor(GA) and interpolate linearly between the two
#     bracketing centiles, EXTRAPOLATING past the outermost pair before
#     clamping to [0, 100]. FetalGPSX clamps instead of extrapolating; the two
#     implementations disagree with each other in the tails.
#
# Nothing here is a source of truth for the library. It records how another
# implementation behaves.
module FetalGPS
  module_function

  # --- normal distribution, no gems ----------------------------------------

  def norm_cdf(z)
    0.5 * Math.erfc(-z / Math.sqrt(2))
  end

  # Acklam's rational approximation, |error| < 1.15e-9
  def norm_inv(p)
    raise ArgumentError, "p must be in (0,1)" unless p > 0 && p < 1

    a = [-3.969683028665376e+01,  2.209460984245205e+02, -2.759285104469687e+02,
          1.383577518672690e+02, -3.066479806614716e+01,  2.506628277459239e+00]
    b = [-5.447609879822406e+01,  1.615858368580409e+02, -1.556989798598866e+02,
          6.680131188771972e+01, -1.328068155288572e+01]
    c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
         -2.549732539343734e+00,  4.374664141464968e+00,  2.938163982698783e+00]
    d = [ 7.784695709041462e-03,  3.224671290700398e-01,  2.445134137142996e+00,
          3.754408661907416e+00]
    lo, hi = 0.02425, 1 - 0.02425

    if p < lo
      q = Math.sqrt(-2 * Math.log(p))
      (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
    elsif p <= hi
      q = p - 0.5
      r = q * q
      (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
        (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    else
      q = Math.sqrt(-2 * Math.log(1 - p))
      -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
    end
  end

  # --- EFW formulas (mm in, grams out) -------------------------------------

  def efw_hadlock3(ac_mm, fl_mm, hc_mm)
    ac = ac_mm / 10.0
    fl = fl_mm / 10.0
    hc = hc_mm / 10.0
    (10**(1.326 + 0.0438 * ac + 0.158 * fl + 0.0107 * hc - 0.00326 * ac * fl)).round(1)
  end

  def efw_hadlock4(bpd_mm, hc_mm, ac_mm, fl_mm)
    bpd = bpd_mm / 10.0
    hc  = hc_mm / 10.0
    ac  = ac_mm / 10.0
    fl  = fl_mm / 10.0
    (10**(1.3596 + 0.0064 * hc + 0.0424 * ac + 0.174 * fl +
          0.00061 * bpd * ac - 0.00386 * ac * fl)).round(1)
  end

  def efw_intergrowth(ac_mm, hc_mm)
    a = ac_mm / 1000.0
    Math.exp(5.08482 - 54.06633 * a**3 - 95.80076 * (a**3) * Math.log(a) +
             3.13637 * (hc_mm / 1000.0)).round(1)
  end

  # Their data3/data4 split. Returns [efw, formula_id].
  def select_efw(ac_mm:, hc_mm:, fl_mm:, bpd_mm: nil)
    return [nil, nil] if ac_mm.nil? || hc_mm.nil? || fl_mm.nil?
    return [efw_hadlock3(ac_mm, fl_mm, hc_mm), "hadlock_hc_ac_fl"] if bpd_mm.nil?

    [efw_hadlock4(bpd_mm, hc_mm, ac_mm, fl_mm), "hadlock_bpd_hc_ac_fl"]
  end

  # --- charts derived from a normal distribution ---------------------------

  # sd_pct defaults to THEIR 0.127. Pass 0.133 for ours.
  def hadlock_centile(efw, ga_weeks, sd_pct: 0.127)
    return nil unless ga_weeks.between?(10, 41)

    mu = Math.exp(0.578 + 0.332 * ga_weeks - 0.00354 * ga_weeks**2)
    (norm_cdf((efw - mu) / (sd_pct * mu)) * 100).round(1)
  end

  def fmf_centile(efw, ga_days)
    ga_weeks = ga_days / 7.0
    return nil unless ga_weeks >= 20 && ga_weeks < 43

    x  = ga_days - 199
    mn = 3.0893 + 0.00835 * x - 0.00002965 * x**2 - 0.00000006062 * x**3
    sd = 0.02464 + 0.0000564 * ga_days
    (norm_cdf((Math.log10(efw) - mn) / sd) * 100).round(1)
  end

  def intergrowth_centile(efw_int, ga_weeks)
    return nil unless ga_weeks.between?(22, 40)

    l  = -4.257629 - 2162.234 * ga_weeks**-2 + 0.0002301829 * ga_weeks**3
    mu = 4.956737 + 0.0005019687 * ga_weeks**3 -
         0.0001227065 * ga_weeks**3 * Math.log(ga_weeks)
    s  = 1e-4 * (-6.997171 + 0.057559 * ga_weeks**3 -
                 0.01493946 * ga_weeks**3 * Math.log(ga_weeks))
    y  = Math.log(efw_int)
    z  = l.zero? ? Math.log(y / mu) / s : (((y / mu)**l) - 1) / (s * l)
    (norm_cdf(z) * 100).round(1)
  end

  # --- table-based charts ---------------------------------------------------

  # Their interp(): bracket the value, draw a straight line through the two
  # surrounding centiles, extrapolate past the ends, then clamp and round.
  def interp(efw, centiles, values)
    pairs = values.each_with_index
                  .reject { |v, _| v.nil? }
                  .map { |v, i| [v, centiles[i]] }
                  .sort_by(&:first)
    v = pairs.map(&:first)
    c = pairs.map(&:last)

    if efw >= v.last
      lo, hi = v.length - 2, v.length - 1
    elsif efw <= v.first
      lo, hi = 0, 1
    else
      hi = v.index { |x| x >= efw }
      lo = hi - 1
    end

    out = c[lo] + (c[hi] - c[lo]) * (efw - v[lo]) / (v[hi] - v[lo])
    out.clamp(0.0, 100.0).round(1)
  end

  NICHD_CENTILES = [3, 5, 10, 50, 90, 95, 97].freeze
  NICHD_KEYS     = %w[p3 p5 p10 p50 p90 p95 p97].freeze
  WHO_CENTILES   = [2.5, 5, 10, 25, 50, 75, 90, 95, 97.5].freeze
  WHO_KEYS       = %w[p2_5 p5 p10 p25 p50 p75 p90 p95 p97_5].freeze

  # Loads data/percentiles/*.csv once and answers table lookups.
  class Tables
    require "csv"

    def initialize(nichd_path:, who_path:)
      @nichd = index(nichd_path, %w[group ga_weeks])
      @who   = index(who_path,   %w[sex ga_weeks])
    end

    def nichd_centile(efw, ga_weeks, race)
      return nil unless ga_weeks.between?(10, 42)

      row = @nichd[[race.to_s.downcase, ga_weeks.floor.to_s]]
      return nil if row.nil?

      FetalGPS.interp(efw, NICHD_CENTILES, NICHD_KEYS.map { |k| row[k].to_f })
    end

    def who_centile(efw, ga_weeks, sex)
      return nil unless ga_weeks.between?(14, 40)

      key = %w[male female].include?(sex.to_s.downcase) ? sex.to_s.downcase : "combined"
      row = @who[[key, ga_weeks.floor.to_s]]
      return nil if row.nil?

      values = WHO_KEYS.map { |k| row[k].to_s.empty? ? nil : row[k].to_f }
      FetalGPS.interp(efw, WHO_CENTILES, values)
    end

    private

    def index(path, keys)
      CSV.read(path, headers: true).each_with_object({}) do |r, h|
        h[keys.map { |k| r[k] }] = r
      end
    end
  end

  # --- the whole pipeline, as FetalGPS runs it ------------------------------

  def call(tables:, ga_days:, ac_mm: nil, hc_mm: nil, fl_mm: nil, bpd_mm: nil,
           efw: nil, sex: nil, race: nil)
    ga_weeks = ga_days / 7.0
    formula = nil
    if efw.nil?
      efw, formula = select_efw(ac_mm: ac_mm, hc_mm: hc_mm, fl_mm: fl_mm, bpd_mm: bpd_mm)
    end
    efw_int = ac_mm && hc_mm ? efw_intergrowth(ac_mm, hc_mm) : efw

    {
      ga_weeks: ga_weeks.round(6),
      efw_g: efw,
      efw_formula: formula,
      efw_intergrowth_g: efw_int,
      hadlock: efw && hadlock_centile(efw, ga_weeks),
      fmf: efw && fmf_centile(efw, ga_days),
      intergrowth21: efw_int && intergrowth_centile(efw_int, ga_weeks),
      nichd: efw && race && tables.nichd_centile(efw, ga_weeks, race),
      who: efw && tables.who_centile(efw, ga_weeks, sex)
    }
  end
end
