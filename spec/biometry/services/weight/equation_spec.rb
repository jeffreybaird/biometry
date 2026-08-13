# frozen_string_literal: true

# Unit layer. The Hadlock coefficients are not published as a `coefficients:`
# block anywhere in data/hadlock.yml — only as the `equation:` strings — so the
# only way to reach them without hand-transcribing a clinical constant into
# Ruby is to parse them. The grammar is closed: a sum of signed terms, each a
# numeric coefficient optionally multiplied by named variables.
RSpec.describe Biometry::Services::Weight::Equation do
  let(:formulas) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'hadlock.yml').first[:efw_formulas]
  end

  # bpd_hc_ac_fl is unverified, so load_manifest prunes it and no service will
  # ever see it. Its equation is still the only two-line one in the repo, and
  # it is the row slice 4 is blocked on, so the parser has to keep handling
  # that shape. Read past the loader deliberately, and only for the string's
  # shape — no value transcribed from this row is asserted anywhere.
  let(:unpruned) do
    YAML.safe_load_file(Biometry::DATA_ROOT / 'hadlock.yml', symbolize_names: true)
  end

  describe '.parse' do
    context 'when the equation is written on one line' do
      subject(:equation) { described_class.parse(formulas[:hc_ac_fl][:equation]) }

      it 'names the variables the equation reads, lowercased' do
        expect(equation.variables).to contain_exactly(:hc, :ac, :fl)
      end

      it 'ignores the left-hand side rather than treating log10 as a variable' do
        expect(equation.variables).not_to include(:w, :log10)
      end
    end

    # `equation: >` in data/hadlock.yml does not fold this one to a single
    # line: the continuation is more-indented, so YAML keeps the newline. The
    # string arrives with an embedded "\n", run-on spaces and a trailing "\n".
    context 'when the equation spans two lines' do
      subject(:equation) do
        described_class.parse(unpruned[:efw_formulas][:bpd_hc_ac_fl][:equation])
      end

      it 'reads the terms on both sides of the line break' do
        expect(equation.variables).to contain_exactly(:bpd, :hc, :ac, :fl)
      end

      it 'evaluates despite the newlines the block scalar leaves in the string' do
        expect(equation.evaluate(bpd: 9.0, hc: 33.0, ac: 34.0, fl: 7.0)).to be_a(Float)
      end
    end

    context 'when the equation uses a form outside the grammar' do
      # INTERGROWTH's equation has parentheses, a cube and a natural log. It is
      # deliberately not parsed: its coefficients are published as a
      # `coefficients:` block and its functional form belongs in code.
      let(:intergrowth) do
        Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'intergrowth21.yml').first
      end

      it 'refuses the INTERGROWTH equation rather than parsing part of it' do
        expect { described_class.parse(intergrowth[:efw][:equation]) }
          .to raise_error(Biometry::MalformedReferenceData)
      end

      it 'refuses an exponent, which no Hadlock formula uses' do
        expect { described_class.parse('log10(W) = 1.326 + 0.0107*HC^2') }
          .to raise_error(Biometry::MalformedReferenceData)
      end

      it 'refuses a string with no equals sign to split on' do
        expect { described_class.parse('1.304 + 0.05281*AC') }
          .to raise_error(Biometry::MalformedReferenceData)
      end

      # Zero terms would construct an Equation that evaluates to 0 for every
      # input: a silent wrong weight, which is what this parser exists to
      # prevent.
      it 'refuses an equals sign with nothing after it' do
        expect { described_class.parse('log10(W) = ') }
          .to raise_error(Biometry::MalformedReferenceData)
      end

      it 'refuses a right-hand side that is only whitespace' do
        expect { described_class.parse("log10(W) =   \n   ") }
          .to raise_error(Biometry::MalformedReferenceData)
      end

      it 'names the equation it could not parse' do
        malformed = 'log10(W) = 1.326 + banana*HC'
        expect { described_class.parse(malformed) }
          .to raise_error(Biometry::MalformedReferenceData, /#{Regexp.escape(malformed)}/)
      end
    end
  end

  describe '#evaluate' do
    # Synthetic coefficients: this example is about the grammar, not about any
    # published constant.
    subject(:equation) { described_class.parse('log10(W) = 2 + 3*X - 0.5*X*Y') }

    it 'sums the signed terms' do
      expect(equation.evaluate(x: 2, y: 4)).to eq(4.0)
    end

    it 'multiplies a term by every variable named in it' do
      expect(equation.evaluate(x: 1, y: 10)).to eq(0.0)
    end

    it 'ignores values it has no term for' do
      expect(equation.evaluate(x: 2, y: 4, bpd: 9.0)).to eq(4.0)
    end

    context 'when the leading term is negative' do
      subject(:equation) { described_class.parse('log10(W) = -1.5 + 2*X') }

      it 'subtracts it' do
        expect(equation.evaluate(x: 1)).to eq(0.5)
      end
    end
  end
end
