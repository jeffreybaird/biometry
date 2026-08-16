# frozen_string_literal: true

require 'json'

# Unit layer. The report as data, before anybody serialises it.
#
# A web consumer wants the document, not a string it has to parse back. So the
# shape JsonReport was building privately becomes a value in its own right, and
# JsonReport becomes the one line that generates JSON from it.
#
# Which means the pin here is equality with what JsonReport prints, computed
# rather than retyped: a hand-written expectation of the whole document would
# agree with whichever of the two was written second, and say nothing about the
# other. Everything JsonReport's own spec asserts about the document's contents
# still holds there and is not repeated.
RSpec.describe Biometry::Services::Report::Document do
  subject(:document) { described_class.new.call(**arguments) }

  let(:ga) { ComposedReport.ga_of }
  let(:scan) { ComposedReport.scan_of }
  let(:study) { Biometry::Study.new(scan: scan, ga: ga, growth: ComposedReport.growth) }
  let(:redating) { ComposedReport.redating(discrepancy: 12) }
  let(:arguments) do
    { dating: ComposedReport.dating, ga: ga, studies: [study], redating: redating }
  end

  def printed(**overrides)
    Biometry::Presentation::JsonReport.new.call(**arguments, **overrides)
  end

  it 'answers with the document itself rather than with a rendering of it' do
    expect(document).to be_a(Hash)
  end

  it 'keys it by symbol, a Ruby caller reaching for :dating rather than for a string' do
    expect(document.keys).to include(:gestational_age, :dating, :studies, :sources, :notes)
  end

  # The whole of the refactor, stated once: the printed report is this document
  # and nothing besides.
  it 'is exactly the document the JSON report prints' do
    expect(JSON.parse(JSON.generate(document))).to eq(JSON.parse(printed))
  end

  it 'is still exactly that document when no redating was asked for' do
    without = described_class.new.call(**arguments, redating: nil)
    expect(JSON.parse(JSON.generate(without))).to eq(JSON.parse(printed(redating: nil)))
  end

  # The sources block is assembled during the merge JsonReport used to do at
  # the end, so it is the part a careless extraction drops.
  it 'cites every paper the rendering cites' do
    expect(document[:sources]).to eq(JSON.parse(printed)['sources'])
  end

  it 'carries the notes the rendering carries' do
    expect(document[:notes]).to eq(JSON.parse(printed)['notes'])
  end

  # A key holding null reads as a question that was asked and could not be
  # answered, which is the same rule the rendering already keeps.
  context 'when no redating was asked for' do
    subject(:document) { described_class.new.call(**arguments, redating: nil) }

    it 'carries no entry for one' do
      expect(document).not_to have_key(:redating)
    end

    it 'is otherwise the document it was before the entry existed' do
      expect(document).to eq(described_class.new.call(**arguments.except(:redating)))
    end
  end

  context 'when a redating was asked for' do
    it 'carries the decision under its own key' do
      expect(document[:redating][:recommendation]).to eq(redating.value!.recommendation)
    end
  end
end
