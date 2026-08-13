# frozen_string_literal: true

module Fixtures
  # Collects results and prints them. Diagnostics go to the stream it is
  # given; the process exit status is the machine-readable part.
  class Report
    EQUATION_FIXTURES = {
      'hadlock.yml' => [
        '1991 median equation at selected weeks',
        '1991 centiles at 32 weeks',
        '1991 centiles at 40 weeks'
      ],
      'intergrowth21.yml' => [
        'worked example, LMS parameters at 30+0',
        '3rd centile at 30+0',
        'Table S1 centiles at 33+0'
      ]
    }.freeze

    def initialize(io)
      @io = io
      @passed = 0
      @failed = []
      @pending = 0
    end

    def section(title)
      @io.puts
      @io.puts(title)
      @io.puts('-' * title.length)
    end

    def check(name, actual, expected)
      if actual == expected
        pass(name)
      else
        fail_with(name, "expected #{expected.inspect}, got #{actual.inspect}")
      end
    end

    def pass(name)
      @passed += 1
      @io.puts("  PASS    #{name}")
    end

    def fail_with(name, detail)
      @failed << "#{name}: #{detail}"
      @io.puts("  FAIL    #{name} — #{detail}")
    end

    def pending(name, reason)
      @pending += 1
      @io.puts("  PENDING #{name} — #{reason}")
    end

    def pending_equation_fixtures
      section('Equation-backed fixtures (slices 3 and 4)')
      EQUATION_FIXTURES.each { |file, names| pend_all(file, names) }
    end

    def summary
      @io.puts
      @io.puts("#{@passed} passed, #{@failed.length} failed, #{@pending} pending")
      @failed.empty? ? 0 : 1
    end

    private

    def pend_all(file, names)
      names.each { |name| pending("#{file}: #{name}", 'needs the formula code from slice 3/4') }
    end
  end
end
