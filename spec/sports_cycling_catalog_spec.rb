require_relative 'spec_helper'
require_relative '../app/sports_catalog'

# STUFF #72 — cycling as a sport category. New catalog entries
# under 'cycling' covering both UCI WorldTours, 5 Grand Tours,
# 5 Monuments, and the road World Championships. Player follows
# work via each team's :players chips, same as NBA / tennis.

RSpec.describe SportsCatalog, 'cycling sport (STUFF #72)' do
  it 'declares the cycling sport with both UCI WorldTour seasons' do
    sport = SportsCatalog.find_sport('cycling')
    expect(sport).not_to be_nil
    expect(sport[:name]).to eq('Cycling')
    season_slugs = SportsCatalog.seasons_for('cycling').map { |lg| lg[:slug] }
    expect(season_slugs).to contain_exactly('uci-worldtour-men', 'uci-worldtour-women')
  end

  it 'declares the 3 Grand Tours plus the women\'s stage races' do
    tournament_slugs = SportsCatalog.tournaments_for('cycling').map { |t| t[:slug] }
    expect(tournament_slugs).to include('tour-de-france', 'giro-italia', 'vuelta-espana',
                                         'tour-de-france-femmes', 'vuelta-femenina')
  end

  it 'declares all 5 Monuments + UCI Road Worlds' do
    tournament_slugs = SportsCatalog.tournaments_for('cycling').map { |t| t[:slug] }
    expect(tournament_slugs).to include('milan-san-remo', 'tour-of-flanders', 'paris-roubaix',
                                         'liege-bastogne-liege', 'il-lombardia',
                                         'uci-road-worlds')
  end

  it 'carries notable riders as :players chips on each pro cycling team (so follow-player works)' do
    men_tour = SportsCatalog.find_league('cycling', 'uci-worldtour-men')
    uae = men_tour[:teams].find { |t| t[:slug] == 'uae-team-emirates' }
    expect(uae[:players]).to include('Tadej Pogačar')
    visma = men_tour[:teams].find { |t| t[:slug] == 'visma-lease-a-bike' }
    expect(visma[:players]).to include('Jonas Vingegaard')

    women_tour = SportsCatalog.find_league('cycling', 'uci-worldtour-women')
    sd_worx = women_tour[:teams].find { |t| t[:slug] == 'sd-worx-protime' }
    expect(sd_worx[:players]).to include('Demi Vollering', 'Lotte Kopecky')
  end

  it 'every cycling team has the required catalog keys (slug, name, players)' do
    cycling_teams = %w[uci-worldtour-men uci-worldtour-women].flat_map do |lg_slug|
      SportsCatalog.find_league('cycling', lg_slug)[:teams]
    end
    expect(cycling_teams.length).to eq(13)
    cycling_teams.each do |t|
      expect(t.keys).to include(:slug, :name, :players)
      expect(t[:players]).not_to be_empty
    end
  end
end
