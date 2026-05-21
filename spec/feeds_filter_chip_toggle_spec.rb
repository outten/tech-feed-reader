require_relative 'spec_helper'

# STUFF #43 — clicking the active topic chip on /feeds used to be a
# no-op (the click handler cleared `is-active` from every chip then
# re-added it to the clicked chip). Fix lives in public/feeds-filter.js
# and falls back to the "All" chip on a second-click toggle.
#
# This spec covers the JS source (lightweight grep — full DOM exercise
# is overkill given the surrounding logic), and the two-bar view
# markup that contains the "All" chip with data-topic="".
RSpec.describe 'feeds-filter chip toggle (STUFF #43)' do
  let(:js_path)  { File.expand_path('../public/feeds-filter.js', __dir__) }
  let(:view_path){ File.expand_path('../views/feeds.erb', __dir__) }
  let(:js)       { File.read(js_path) }
  let(:view)     { File.read(view_path) }

  describe 'public/feeds-filter.js' do
    it 'detects the click on the already-active chip' do
      expect(js).to include('wasActive')
      expect(js).to match(/wasActive\s*=\s*c\.classList\.contains\(['"]is-active['"]\)/)
    end

    it 'falls back to the All chip (data-topic="") when toggling off' do
      expect(js).to include('.feeds-filter-chip[data-topic=""]')
    end

    it 'keeps the All chip itself activate-on-click (no toggle loop)' do
      # "If wasActive && NOT isAllChip" — clicking the All chip while
      # it is active should still flip back to itself, not a different
      # chip. The branch must guard on isAllChip.
      expect(js).to include('isAllChip')
    end

    # Without this guard, init() attaching to both DOMContentLoaded AND
    # turbo:load (Turbo 8 fires both on a full page load) double-wires
    # the chips. Each click then runs the handler twice and the second
    # run reverts the active state to "All" — making chips appear dead.
    it 'guards against double-wiring across DOMContentLoaded + turbo:load' do
      expect(js).to match(/dataset\.filterWired/),
        'wireBar must mark each bar as wired (dataset.filterWired) to be idempotent'
    end
  end

  describe 'views/feeds.erb' do
    it 'renders an All chip with data-topic="" in both filter bars' do
      all_chip_count = view.scan(/feeds-filter-chip is-active.*data-topic=""/).length
      expect(all_chip_count).to be >= 2
    end
  end
end
