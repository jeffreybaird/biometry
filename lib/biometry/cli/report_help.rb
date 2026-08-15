# frozen_string_literal: true

module Biometry
  module CLI
    # The report command's help.
    #
    # Held apart from the command so the copy can be read and edited as copy.
    # Every flag says what the quantity is in words, what units it is in, and
    # what the value means — a reader should not have to know that AC is an
    # abdominal circumference in millimetres before they can use this.
    module ReportHelp
      TEXT = <<~HELP
        Usage: biometry report --ga 32w0d [options]

        Estimated fetal weight and growth percentiles across the competing
        international standards, and where they disagree. Formula and chart are
        paired, so the table carries three distinct weights across the four
        standards rather than one weight compared four ways.

        It reports measurements and the sources they came from, and emits no
        classification of any kind.

        Gestation
          --ga WEEKS       Gestational age to read every chart at, written as
                           weeks and days: 32w0d. Required, because choosing
                           between derivations that disagree is not this
                           command's decision to make.
          --at DATE        Reference date the report is taken at, ISO
                           YYYY-MM-DD. Defaults to today, which silently
                           changes the answer, so pass it when reproducing a
                           result.

        Biometry
          --bpd MM         Biparietal diameter: the widest side-to-side span of
                           the fetal skull, in millimetres. Decimals allowed.
          --hc MM          Head circumference, measured around the outer
                           perimeter of the skull, in millimetres.
          --ac MM          Abdominal circumference, measured around the outer
                           border of the body outline, in millimetres.
          --fl MM          Femur length: the full femoral shaft, excluding the
                           distal epiphysis, in millimetres.

        Dating
          --lmp DATE       First day of the last menstrual period, ISO
                           YYYY-MM-DD.
          --cycle DAYS     Menstrual cycle length in days. Naegele assumes 28;
                           a 35-day cycle moves the due date a week later.
          --transfer DATE  Embryo transfer date, ISO YYYY-MM-DD.
          --embryo-day N   Embryo age in days on the day of transfer.
                           3 for a cleavage embryo, 5 for a blastocyst.
                           Required alongside a transfer date, because
                           guessing it is a two-day error in either direction.

        Redating
          --established-edd DATE
                           The due date already established for this
                           pregnancy, ISO YYYY-MM-DD. Requires the other two
                           redating flags alongside it: two of the three
                           describe a comparison with nothing to compare
                           against.
          --established-by HOW
                           How that established date was arrived at: lmp,
                           transfer, crl or biometry. This is not a note on
                           provenance -- a pregnancy dated by IVF, which is
                           transfer here, is never redated by ultrasound, so
                           this flag decides whether any threshold is
                           consulted at all.
          --scan-edd DATE  The due date this scan implies, ISO YYYY-MM-DD.
                           It is compared against the established one; neither
                           date is revised, and the answer is a recommendation
                           with its reasoning.

        Charts
          --sex SEX        Fetal sex, selecting the WHO chart: combined, female
                           or male. Omitted, the combined table is read.
          --stratum GROUP  NICHD chart: white, black, hispanic or asian.
                           Self-reported race and ethnicity, never inferred and
                           never defaulted. Omitted, all four charts print,
                           because NICHD publishes no combined table and the
                           spread between them is the finding.

        Messages
          --hl7 PATH       Read the biometry from an HL7 ORU^R01 observation
                           message at PATH, instead of from the four
                           measurement flags -- pass one or the other, not
                           both. Each OBR in the message is one study.
                           Refused until data/loinc.yml is transcribed: without
                           a mapping no OBX identifier can be named, and a
                           report with nothing in it would read as a fetus
                           nobody measured.

        Output
          --json           Emit the report as JSON on stdout, undecorated. It
                           carries unrounded values where the table rounds a
                           percentile to a whole ordinal.

        Exit codes
          0  a report was produced
          1  nothing could be reported; the refusals still print on stdout
          2  a usage error; stdout stays empty and stderr names the problem
      HELP
    end
  end
end
