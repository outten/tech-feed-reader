require_relative 'spec_helper'
require_relative '../scripts/bump_version'
require 'tempfile'

# STUFF #33A. Unit coverage for the semver-bumper used by
# `make deploy-major/-minor/-patch`. The pure `BumpVersion.bump` arithmetic
# is the load-bearing piece; the file-I/O wrapper is covered by a few
# end-to-end examples using a tempfile.
RSpec.describe BumpVersion do
  describe '.bump (pure)' do
    it 'rolls a major bump and zeroes minor + patch' do
      expect(described_class.bump('1.2.3', 'major')).to eq('2.0.0')
    end

    it 'rolls a minor bump and zeroes patch' do
      expect(described_class.bump('0.9.5', 'minor')).to eq('0.10.0')
    end

    it 'rolls a patch bump' do
      expect(described_class.bump('0.9.0', 'patch')).to eq('0.9.1')
    end

    it 'survives double-digit components without lex-sorting bugs' do
      expect(described_class.bump('0.99.99', 'minor')).to eq('0.100.0')
    end

    it 'raises ArgumentError for unknown kinds' do
      expect { described_class.bump('0.1.0', 'huge') }.to raise_error(ArgumentError, /huge/)
    end

    it 'raises ArgumentError for non-semver input' do
      expect { described_class.bump('v0.1', 'patch') }.to raise_error(ArgumentError, /not semver/)
    end
  end

  describe '.run end-to-end (with stubbed VERSION_FILE)' do
    around do |ex|
      tmp = Tempfile.create(['VERSION', ''])
      tmp.write("0.9.0\n")
      tmp.close
      original = described_class::VERSION_FILE
      described_class.send(:remove_const, :VERSION_FILE)
      described_class.const_set(:VERSION_FILE, tmp.path)
      begin
        ex.run
      ensure
        described_class.send(:remove_const, :VERSION_FILE)
        described_class.const_set(:VERSION_FILE, original)
        File.unlink(tmp.path) if File.exist?(tmp.path)
      end
    end

    it 'rewrites VERSION on success and prints the new version' do
      expect { described_class.run(['patch']) }
        .to output("0.9.1\n").to_stdout
      expect(File.read(described_class::VERSION_FILE)).to eq("0.9.1\n")
    end

    it 'exits 1 with a helpful message on a bogus kind' do
      expect { described_class.run(['huge']) }
        .to output(/unknown kind/).to_stderr
        .and raise_error(SystemExit)
    end

    it 'exits 1 when no argument is given' do
      expect { described_class.run([]) }
        .to output(/missing argument/).to_stderr
        .and raise_error(SystemExit)
    end
  end

  # The AppVersion module reads the VERSION file at load time and
  # freezes the result. We can't easily re-exercise that without
  # reloading the file, but we CAN sanity-check that the constant is
  # populated and looks semver-shaped (or is 'unknown' in a context
  # where the file isn't present).
  describe 'AppVersion::SEMVER' do
    it 'is either semver-shaped or the literal "unknown" sentinel' do
      require_relative '../app/version'
      expect(AppVersion::SEMVER).to match(/\A(\d+\.\d+\.\d+|unknown)\z/)
    end
  end
end
