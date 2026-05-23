require_relative 'spec_helper'
require_relative '../app/sports_catalog'

# Roster completeness check — NFL and NBA carry the full league. If
# someone trims a team out of the catalog by accident, this catches
# it; if a real expansion team is added (rare — last one was the
# Houston Texans in 2002), bump the count.
RSpec.describe 'NFL + NBA catalog completeness' do
  describe 'NFL' do
    let(:teams) { SportsCatalog.find_league('football', 'nfl')[:teams] }

    it 'has all 32 teams' do
      expect(teams.length).to eq(32)
    end

    it 'has unique slugs' do
      slugs = teams.map { |t| t[:slug] }
      expect(slugs.uniq.length).to eq(slugs.length)
    end

    it 'has unique ESPN external_ids' do
      ids = teams.map { |t| t[:external_id] }
      expect(ids.uniq.length).to eq(ids.length)
    end

    it 'covers all 32 divisions of slugs (sanity check on individual teams)' do
      expected_slugs = %w[
        eagles cowboys chiefs niners bills
        cardinals falcons ravens panthers bears bengals browns broncos
        lions packers texans colts jaguars raiders chargers rams dolphins
        vikings patriots saints giants jets steelers seahawks buccaneers
        titans commanders
      ]
      expect(teams.map { |t| t[:slug] }).to contain_exactly(*expected_slugs)
    end
  end

  describe 'NBA' do
    let(:teams) { SportsCatalog.find_league('basketball', 'nba')[:teams] }

    it 'has all 30 teams' do
      expect(teams.length).to eq(30)
    end

    it 'has unique slugs' do
      slugs = teams.map { |t| t[:slug] }
      expect(slugs.uniq.length).to eq(slugs.length)
    end

    it 'has unique ESPN external_ids' do
      ids = teams.map { |t| t[:external_id] }
      expect(ids.uniq.length).to eq(ids.length)
    end

    it 'covers all 30 teams (sanity check on individual teams)' do
      expected_slugs = %w[
        sixers celtics lakers warriors bucks
        hawks nets hornets bulls cavaliers mavericks nuggets pistons
        rockets pacers clippers grizzlies heat timberwolves pelicans
        knicks thunder magic suns trail-blazers kings spurs raptors
        jazz wizards
      ]
      expect(teams.map { |t| t[:slug] }).to contain_exactly(*expected_slugs)
    end
  end
end
