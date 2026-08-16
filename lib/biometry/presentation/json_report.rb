# frozen_string_literal: true

require 'json'

module Biometry
  module Presentation
    # The report as JSON on stdout. The document itself is built by
    # Services::Report::Document — this only serializes it, so the CLI and a
    # web consumer cannot disagree about what the report contains.
    class JsonReport
      def call(**report)
        JSON.generate(Services::Report::Document.new.call(**report))
      end
    end
  end
end
