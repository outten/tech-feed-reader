require_relative 'spec_helper'
require_relative '../app/summarizer/extractive'

RSpec.describe Summarizer::Extractive do
  describe '.summarize' do
    it 'returns the whole text if it already fits in the target sentence count' do
      text = 'First sentence. Second sentence. Third sentence.'
      expect(Summarizer::Extractive.summarize(text, sentences: 3)).to eq(text)
    end

    it 'returns empty for empty / whitespace input' do
      expect(Summarizer::Extractive.summarize('')).to eq('')
      expect(Summarizer::Extractive.summarize('   ')).to eq('')
      expect(Summarizer::Extractive.summarize(nil)).to eq('')
    end

    it 'always keeps the first sentence (lead bias)' do
      text = [
        'Anchor opening sentence about completely unrelated stuff.',
        'Cats are excellent. Cats are friendly. Cats love milk.',
        'Dogs run fast. Dogs are loyal. Dogs bark a lot.',
        'Snakes slither.'
      ].join(' ')
      out = Summarizer::Extractive.summarize(text, sentences: 3)
      expect(out).to start_with('Anchor opening sentence')
    end

    it 'preserves original document order in the output' do
      text = 'Alpha sentence first. Beta sentence second. Gamma sentence third. Delta sentence fourth.'
      out = Summarizer::Extractive.summarize(text, sentences: 2)
      ai = out.index('Alpha')
      bi = out.index('Beta') || 9999
      ci = out.index('Gamma') || 9999
      di = out.index('Delta') || 9999
      indices = [ai, bi, ci, di].reject { |x| x == 9999 }
      expect(indices).to eq(indices.sort)
    end

    it 'picks sentences whose tokens overlap with the document term distribution' do
      # "kubernetes" repeats heavily; the kubernetes-mentioning sentence should make the cut.
      text = [
        'Today the weather is sunny in San Francisco.',
        'Kubernetes can be tricky for new users to operate.',
        'Operators package kubernetes know-how into reusable controllers.',
        'Kubernetes networking has many moving parts.',
        'Have a great day.'
      ].join(' ')
      out = Summarizer::Extractive.summarize(text, sentences: 3)
      expect(out.scan(/[Kk]ubernetes/).length).to be >= 1
    end

    it 'discards sentences that are too short to score' do
      text = 'Hi. This is the actual lead sentence about machine learning. Machine learning is broad. Bye.'
      out = Summarizer::Extractive.summarize(text, sentences: 2)
      expect(out).not_to include('Bye.')
    end
  end
end
