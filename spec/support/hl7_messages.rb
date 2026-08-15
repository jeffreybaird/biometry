# frozen_string_literal: true

# Slice 6's messages, built rather than pasted.
#
# A pasted message is unreadable and a message inlined in twenty examples is
# twenty chances for one of them to differ from the others by a pipe. These are
# assembled from named parts, so an example can say what it is parsing --
# "an ORU with a narrative OBX and a malformed one" -- and a reader can see the
# segment that sentence refers to.
#
# Every builder takes the encoding characters it should write itself with, so
# the same fixture can be produced under a vendor's separators and compared
# against the default one. That comparison is the whole point of reading MSH-2
# rather than hardcoding `|^~\&`.
#
# The identifiers here are deliberately not LOINC-shaped. data/ carries no
# LOINC transcription, and a spec asserting on a real code would read as though
# somebody had verified it against the standard. The mapping is the parser's
# argument; these are ours.
module Hl7Messages
  module_function

  # Field and component separators. Repetition, escape and subcomponent stay at
  # their defaults in both, so the vendor example isolates the two separators a
  # parser actually splits on.
  DEFAULT = { field: '|', component: '^' }.freeze
  VENDOR = { field: '!', component: '*' }.freeze

  # HL7 terminates every segment with a carriage return, whatever the file the
  # message arrives in looks like afterwards.
  TERMINATOR = "\r"

  ORU_R01 = %w[ORU R01].freeze
  ADT_A01 = %w[ADT A01].freeze

  CODES = { bpd: 'SPEC-BPD', hc: 'SPEC-HC', ac: 'SPEC-AC', fl: 'SPEC-FL' }.freeze

  NAMES = { bpd: 'Biparietal diameter', hc: 'Head circumference',
            ac: 'Abdominal circumference', fl: 'Femur length' }.freeze

  # What a spec hands the parser. Codes to measurement kinds, nothing else.
  MAPPING = CODES.to_h { |kind, code| [code, kind] }.freeze

  # An observation this library has no mapping for: an amniotic fluid index is
  # a real thing an OB system reports and not a biometric parameter any formula
  # here reads.
  UNMAPPED = 'SPEC-AFI'

  # The whole report as prose, which is how many OB systems ship one.
  NARRATIVE = 'SPEC-REPORT'

  UNMAPPED_NAMES = { UNMAPPED => 'Amniotic fluid index',
                     NARRATIVE => 'Ultrasound report' }.freeze

  # 32w0d biometry, the same numbers ComposedReport builds a Scan from by hand,
  # so a scan parsed out of a message can be weighed against one that was not.
  MILLIMETRES = { bpd: 82, hc: 291, ac: 274, fl: 62 }.freeze

  # The message was sent the morning after the scan, so a parser reading the
  # date off MSH-7 gets a different day from one reading it off OBR-7.
  SENT_AT = '20260814080000'
  OBSERVED_AT = '20260813142500'
  EARLIER_OBSERVED_AT = '20260701090000'

  # Far enough back that the gestation on its own date falls outside every
  # chart's published window, whatever gestation the caller supplies for the
  # reference date.
  DISTANT_OBSERVED_AT = '20260301103000'

  SCAN_DATE = Date.new(2026, 8, 13)
  EARLIER_SCAN_DATE = Date.new(2026, 7, 1)
  DISTANT_SCAN_DATE = Date.new(2026, 3, 1)
  SENT_DATE = Date.new(2026, 8, 14)

  # Numbers a scraper would find in the prose, and which must never reach a
  # caller as measurements.
  NARRATIVE_TEXT = [
    'Single intrauterine pregnancy in cephalic presentation.',
    'Biometry: BPD 8.2 cm, HC 29.1 cm, AC 27.4 cm, FL 6.2 cm.',
    'Estimated fetal weight 1850 g. Amniotic fluid within reference range.'
  ].freeze

  # ------------------------------------------------------------- primitives --

  def message(*segments) = segments.join(TERMINATOR) + TERMINATOR

  def segment(fields, enc: DEFAULT)
    fields.map { |field| Array(field).join(enc[:component]) }.join(enc[:field])
  end

  # MSH-1 is the field separator itself, which is why joining puts it where a
  # first field would otherwise go, and MSH-2 the four remaining characters.
  def msh(type: ORU_R01, enc: DEFAULT)
    segment(['MSH', "#{enc[:component]}~\\&", 'SPECSCANNER', 'SPECSITE', 'BIOMETRY',
             'SPECSITE', SENT_AT, nil, type, 'SPEC00001', 'P', '2.5'], enc: enc)
  end

  # OBR-7 is the observation date and time: when the study was performed.
  def obr(order: 1, observed_at: OBSERVED_AT, enc: DEFAULT)
    segment(['OBR', order.to_s, nil, nil, ['SPEC-US', 'Obstetric ultrasound', 'SPECMAP'],
             nil, nil, observed_at], enc: enc)
  end

  def obx(identifier, value, units: 'mm', set_id: 1, value_type: 'NM', enc: DEFAULT)
    segment(['OBX', set_id.to_s, value_type, coded(identifier), nil, value, units,
             nil, nil, nil, nil, 'F'], enc: enc)
  end

  # OBX-3 is a coded element: identifier, the text a human reads, and the
  # coding system it came from. Only the first component names the observation.
  def coded(identifier)
    return [CODES.fetch(identifier), NAMES.fetch(identifier), 'SPECMAP'] if identifier.is_a?(Symbol)

    [identifier, UNMAPPED_NAMES.fetch(identifier, 'Unmapped observation'), 'SPECMAP']
  end

  # ----------------------------------------------------------- observations --

  def observations(values, units: 'mm', enc: DEFAULT)
    values.each_with_index.map do |(kind, value), index|
      obx(kind, value.to_s, units: units, set_id: index + 1, enc: enc)
    end
  end

  def millimetre_observations(enc: DEFAULT) = observations(MILLIMETRES, enc: enc)

  def centimetre_observations(enc: DEFAULT)
    observations(MILLIMETRES.transform_values { |mm| mm / 10.0 }, units: 'cm', enc: enc)
  end

  # OBX-2 promises a number and OBX-5 carries prose, so the field position that
  # failed is 5.
  def malformed_obx(set_id: 1, enc: DEFAULT)
    obx(:ac, 'see report', set_id: set_id, enc: enc)
  end

  def unmapped_obx(set_id: 1, enc: DEFAULT)
    obx(UNMAPPED, '14.2', units: 'cm', set_id: set_id, enc: enc)
  end

  def narrative_obx(enc: DEFAULT)
    NARRATIVE_TEXT.each_with_index.map do |line, index|
      obx(NARRATIVE, line, units: nil, set_id: index + 1, value_type: 'TX', enc: enc)
    end
  end

  # ---------------------------------------------------------------- reports --

  # One OBR, one observation per biometric parameter, in millimetres.
  def full(enc: DEFAULT) = message(msh(enc: enc), obr(enc: enc), *millimetre_observations(enc: enc))

  def in_centimetres(enc: DEFAULT)
    message(msh(enc: enc), obr(enc: enc), *centimetre_observations(enc: enc))
  end

  # Two studies in one message. Different days, different observations: one
  # scan with twice the observations would have neither.
  def two_scans
    message(msh,
            obr(order: 1, observed_at: EARLIER_OBSERVED_AT), obx(:ac, '240'),
            obr(order: 2, observed_at: OBSERVED_AT), obx(:ac, '274'), obx(:fl, '62', set_id: 2))
  end

  # Two studies, six weeks apart, reporting the identical biometry.
  #
  # Identical on purpose: the weights are then the same to the gram, so any
  # difference between the two tables is the gestation each was read at and
  # nothing else. Read both at the gestation the caller typed and the two
  # tables come out the same, which is the error this fixture exists to make
  # visible.
  def two_full_studies
    message(msh,
            obr(order: 1, observed_at: EARLIER_OBSERVED_AT), *millimetre_observations,
            obr(order: 2, observed_at: OBSERVED_AT), *millimetre_observations)
  end

  # One study whose own gestation is inside every chart's window, and one far
  # enough back that no chart publishes a column for it.
  def two_studies_one_beyond_the_charts
    message(msh,
            obr(order: 1, observed_at: DISTANT_OBSERVED_AT), *millimetre_observations,
            obr(order: 2, observed_at: OBSERVED_AT), *millimetre_observations)
  end

  # A study nothing could be read from, alongside one that reports in full. The
  # first is not a scan of a fetus nobody measured; it is a study whose
  # observations this library has no vocabulary for, and it says so on stderr.
  def two_studies_one_unreadable
    message(msh,
            obr(order: 1, observed_at: EARLIER_OBSERVED_AT), unmapped_obx,
            obr(order: 2, observed_at: OBSERVED_AT), *millimetre_observations)
  end

  def with_unmapped_observation
    message(msh, obr, obx(:ac, '274'), unmapped_obx(set_id: 2))
  end

  # Everything a chart needs, and one observation besides that nothing names:
  # a message that yields a whole report and a diagnostic at the same time.
  def full_with_unmapped_observation
    message(msh, obr, *millimetre_observations, unmapped_obx(set_id: MILLIMETRES.length + 1))
  end

  # The same shape, with the extra observation unreadable rather than unnamed:
  # a repeated abdominal circumference whose value is prose. MSH, OBR and four
  # observations put it at segment 7, and the value is field 5.
  def full_with_malformed_observation
    message(msh, obr, *millimetre_observations, malformed_obx(set_id: MILLIMETRES.length + 1))
  end

  def with_malformed_observation
    message(msh, obr, malformed_obx(set_id: 1), obx(:fl, '62', set_id: 2))
  end

  # The first OBR carries no observation date at all. The second is intact.
  def with_undated_study
    message(msh,
            obr(order: 1, observed_at: nil), obx(:ac, '240'),
            obr(order: 2, observed_at: OBSERVED_AT), obx(:ac, '274'))
  end

  def in_units(units, value: '274') = message(msh, obr, obx(:ac, value, units: units))

  def narrative = message(msh, obr, *narrative_obx)

  def narrative_alongside_discrete
    message(msh, obr, *narrative_obx, obx(:ac, '274', set_id: NARRATIVE_TEXT.length + 1))
  end

  def not_an_oru = message(msh(type: ADT_A01), obr, *millimetre_observations)

  def without_msh = message(obr, *millimetre_observations)

  def without_ac
    message(msh, obr, *observations(MILLIMETRES.except(:ac)))
  end
end
