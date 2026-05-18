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

  # The AppVersion::SEMVER constant freezes one resolve_semver call at
  # module load; the resolution logic itself (refactored to a class
  # method for testability) is exercised directly below across all
  # three branches.
  describe 'AppVersion' do
    before { require_relative '../app/version' }

    it 'SEMVER is either semver-shaped or the literal "unknown" sentinel' do
      expect(AppVersion::SEMVER).to match(/\A(\d+\.\d+\.\d+|unknown)\z/)
    end

    describe '.resolve_semver' do
      around do |ex|
        prior = ENV.fetch('APP_VERSION', nil)
        ex.run
      ensure
        ENV['APP_VERSION'] = prior
      end

      it 'returns ENV[APP_VERSION] when set to a non-empty value' do
        ENV['APP_VERSION'] = '1.2.3'
        expect(AppVersion.resolve_semver).to eq('1.2.3')
      end

      it 'falls through to the VERSION file when ENV is empty string' do
        # The bug that motivated the refactor: Docker's `ENV X=${X}`
        # bakes APP_VERSION="" when no build-arg is in scope.
        ENV['APP_VERSION'] = ''
        expect(AppVersion.resolve_semver).to match(/\A\d+\.\d+\.\d+\z/)
      end

      it 'falls through to the VERSION file when ENV is unset' do
        ENV.delete('APP_VERSION')
        expect(AppVersion.resolve_semver).to match(/\A\d+\.\d+\.\d+\z/)
      end

      it 'returns "unknown" when ENV is empty AND the file read raises' do
        ENV['APP_VERSION'] = ''
        allow(File).to receive(:read).with(AppVersion::VERSION_FILE).and_raise(Errno::ENOENT)
        expect(AppVersion.resolve_semver).to eq('unknown')
      end

      it 'strips whitespace from both ENV and file contents' do
        ENV['APP_VERSION'] = "  2.0.0\n"
        expect(AppVersion.resolve_semver).to eq('2.0.0')
      end
    end
  end
end
