# frozen_string_literal: true

module Fixtures
  # Collects results and prints them. Diagnostics go to the stream it is
  # given; the process exit status is the machine-readable part.
  class Report
    # Everything else is now driven through a real adapter. This one asserts
    # intermediate LMS parameters, which no public interface exposes — and
    # should not, since they are a step in a calculation rather than a result.
    EQUATION_FIXTURES = {
      'intergrowth21.yml' => ['worked example, LMS parameters at 30+0']
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
      section('Fixtures with no public interface to check them against')
      EQUATION_FIXTURES.each { |file, names| pend_all(file, names) }
    end

    def summary
      @io.puts
      @io.puts("#{@passed} passed, #{@failed.length} failed, #{@pending} pending")
      @failed.empty? ? 0 : 1
    end

    private

    def pend_all(file, names)
      names.each { |name| pending("#{file}: #{name}", 'asserts an intermediate value') }
    end
  end
end
