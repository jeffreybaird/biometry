# frozen_string_literal: true

module Fixtures
  # INTERGROWTH's EFW fixture became checkable when slice 3 landed: it runs the
  # real service over the real manifest. Its LMS and centile fixtures still
  # need slice 4.
  module Intergrowth
    FIXTURE = 'worked example, EFW'

    module_function

    def call(report)
      report.section('INTERGROWTH EFW (slice 3 — checkable now)')
      manifest = Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'intergrowth21.yml')
      fixture = manifest[:fixtures].find { |f| f[:name] == FIXTURE }

      run(report, manifest, fixture)
    end

    def run(report, manifest, fixture)
      expected = fixture[:expect][:efw_g]
      tolerance = fixture[:tolerance_g]
      name = "#{describe(fixture[:inputs])} -> #{expected} g (+/- #{tolerance})"
      grams = evaluate(manifest, fixture[:inputs])

      return report.pass(name) if (grams - expected).abs <= tolerance

      report.fail_with(name, "got #{grams.round(1)} g")
    end

    def evaluate(manifest, inputs)
      Biometry::Services::Weight::Intergrowth
        .new(manifest: manifest)
        .call(scan_for(inputs))
        .value!
        .value
    end

    def scan_for(inputs)
      measurements = inputs.map do |key, cm|
        Biometry::Measurement.new(kind: key.to_s.delete_suffix('_cm').to_sym, mm: cm * 10)
      end
      Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: measurements)
    end

    def describe(inputs)
      inputs.map { |key, cm| "#{key.to_s.delete_suffix('_cm').upcase} #{cm} cm" }.join(', ')
    end
  end
end
