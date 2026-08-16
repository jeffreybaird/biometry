# frozen_string_literal: true

# Integration layer. One report, composed from the services that own each part
# of it, for a caller that is not the CLI.
#
# The command already knew how to do this — read the dating derivations, read
# each study at the gestation on its own date, ask for a redating when one was
# asked for — but it knew it inside a method that also wrote to a stream and
# returned an exit code. A web app cannot reach any of that, and a second
# composition written for it would be a second place where "what a report is"
# is decided.
#
# So every example here compares against the service it delegates to, called
# directly with the same inputs. A number retyped here would pass whether or
# not the wiring is right.
RSpec.describe Biometry::Services::Report::Builder do
  subject(:report) { builder.call(**request) }

  let(:context) { Biometry.load }
  let(:builder) { described_class.new(manifests: context.manifests, tables: context.tables) }
  let(:ga) { ComposedReport.ga_of }
  let(:request) do
    { scans: [ComposedReport.scan_of], ga: ga, at: ComposedReport::REFERENCE_DATE,
      lmp: ComposedReport::LMP_DATE, cycle_length: 28,
      transfer_date: ComposedReport::TRANSFER_DATE, embryo_day: ComposedReport::EMBRYO_DAY,
      sex: :female, stratum: nil }
  end

  def dated_directly
    Biometry::Services::Dating::AllDerivations.new.call(
      reference_date: ComposedReport::REFERENCE_DATE, lmp: ComposedReport::LMP_DATE,
      cycle_length: 28, transfer_date: ComposedReport::TRANSFER_DATE,
      embryo_day: ComposedReport::EMBRYO_DAY
    ).value!
  end

  def studied_directly(scans, **overrides)
    rows = Biometry::Services::Report::GrowthRows.new(manifests: context.manifests,
                                                      tables: context.tables)
    Biometry::Services::Report::Studies.new(rows: rows).call(
      scans, ga: ga, at: ComposedReport::REFERENCE_DATE, sex: :female,
             stratum: nil, **overrides
    )
  end

  # The redating the report is asked for, and the one ComposedReport builds by
  # hand from the same manifest, are the same question: an established date at
  # a gestation comfortably inside a band, and a scan twelve days off it.
  def established_edd
    ComposedReport.established_edd(ComposedReport.inside_band(ComposedReport.band_with_caveat))
  end

  def redating_request
    { established_edd: established_edd, established_by: :lmp,
      proposed_edd: established_edd + 12 }
  end

  it 'answers with a report rather than with a rendering of one' do
    expect(report).to be_a(Biometry::Report)
  end

  describe 'the dating derivations' do
    it 'offers the derivations the service offers, refusals included' do
      expect(report.dating.keys).to eq(%i[lmp transfer crl biometry])
    end

    it 'unwraps them, a caller reaching for :lmp rather than for a Result of a hash' do
      expect(report.dating).to be_a(Hash)
    end

    it 'dates the pregnancy as the service dates it' do
      expect(report.dating.transform_values { |each| each.success? && each.value!.edd })
        .to eq(dated_directly.transform_values { |each| each.success? && each.value!.edd })
    end

    it 'refuses what the service refuses, for the same reason' do
      expect(report.dating[:crl].failure).to eq(dated_directly[:crl].failure)
    end
  end

  describe 'the studies' do
    it 'carries one study per scan' do
      two = request.merge(scans: [ComposedReport.scan_of, ComposedReport.scan_of])
      expect(builder.call(**two).studies.length).to eq(2)
    end

    it 'reads every chart the registry serves' do
      expect(report.studies.first.growth.map { |row| row[:standard] }.uniq)
        .to match_array(context.charts.keys)
    end

    it 'reads them as the studies service reads them' do
      expect(report.studies.first.growth.map { |row| row[:report].success? })
        .to eq(studied_directly(request[:scans]).first.growth.map { |row| row[:report].success? })
    end

    it 'weighs the fetus as the studies service weighs it' do
      expect(report.studies.first.growth.map { |row| row[:weight].value!.value })
        .to eq(studied_directly(request[:scans]).first.growth.map { |row| row[:weight].value!.value })
    end

    # A scan taken weeks before the reference date is read at the gestation on
    # its own date. Read at the supplied one it is wrong by exactly those days,
    # and wrong in the most convincing way available.
    context 'when a scan was taken before the date the gestation was supplied for' do
      let(:earlier) do
        Biometry::Scan.new(date: ComposedReport::REFERENCE_DATE - 42,
                           measurements: ComposedReport.scan_of.measurements)
      end

      it 'reads it at the gestation on its own date' do
        expect(builder.call(**request, scans: [earlier]).studies.first.ga.days)
          .to eq(ga.days - 42)
      end

      it 'reads it as the studies service reads it' do
        expect(builder.call(**request, scans: [earlier]).studies.first.ga)
          .to eq(studied_directly([earlier]).first.ga)
      end
    end
  end

  # Absent rather than refused when nobody asked: a report that carried a
  # failed redating nobody requested reads as a question that was asked.
  describe 'the redating' do
    context 'when no established date was supplied' do
      it 'carries none' do
        expect(report.redating).to be_nil
      end
    end

    context 'when an established date, its derivation and a proposed date were supplied' do
      subject(:report) { builder.call(**request, **redating_request) }

      it 'carries a result the caller branches on' do
        expect(report.redating).to be_success
      end

      it 'decides as the redating service decides' do
        expect(report.redating.value!.recommendation)
          .to eq(ComposedReport.redating(discrepancy: 12).value!.recommendation)
      end

      it 'measures the discrepancy the service measures' do
        expect(report.redating.value!.discrepancy_days)
          .to eq(ComposedReport.redating(discrepancy: 12).value!.discrepancy_days)
      end

      it 'indexes it at the date the report was asked for' do
        expect(report.redating.value!.indexing_ga)
          .to eq(ComposedReport.redating(discrepancy: 12).value!.indexing_ga)
      end
    end
  end

  # The one question the CLI asks of a finished report, and the reason it is on
  # the report rather than in the command: a web app answering "did anything
  # come back" must answer it the same way.
  describe '#reportable?' do
    it 'is true when anything at all could be reported' do
      expect(report).to be_reportable
    end

    context 'when no dating input arrived and no chart could be read' do
      subject(:report) do
        builder.call(**request, scans: [unmeasured], lmp: nil, transfer_date: nil)
      end

      let(:unmeasured) do
        Biometry::Scan.new(date: ComposedReport::REFERENCE_DATE, measurements: [])
      end

      it 'is false, every derivation and every row having refused' do
        expect(report).not_to be_reportable
      end

      it 'still carries the refusals, a report of nothing not being no report' do
        expect(report.studies.first.growth.map { |row| row[:report].failure.first }.uniq)
          .to eq([:insufficient_data])
      end
    end
  end

  # What the report is for: handing to the document service. Data's own #to_h
  # already names the four members Document takes, so there is no second
  # spelling of the same list — the members are the arguments.
  describe '#to_h' do
    it 'names the arguments the document service takes' do
      expect(report.to_h.keys).to match_array(%i[dating ga studies redating])
    end

    it 'builds a document from a report without anything in between' do
      expect(Biometry::Services::Report::Document.new.call(**report.to_h))
        .to include(:gestational_age, :dating, :studies, :sources)
    end

    it 'carries the redating through when one was asked for' do
      asked = builder.call(**request, **redating_request)
      expect(Biometry::Services::Report::Document.new.call(**asked.to_h))
        .to have_key(:redating)
    end
  end
end
