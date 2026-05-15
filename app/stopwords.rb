require 'set'

# STUFF #28.5 — single home for all tokenizer stopword lists.
#
# Three lists, three purposes:
#   * GENERAL   — single-word topic + summary filter. The big list.
#                 Common English (the / and / etc.) plus a "site &
#                 social boilerplate" bucket (comments / subscribe /
#                 instagram), filler verbs (get / make / said), URL
#                 fragments (com / org / www), time-vague words
#                 (today / year), and month/day name shorthand. Used
#                 by Summarizer::Extractive and Recommendation.
#                 ~250 words.
#   * PHRASE    — bigram-rejection list for adjacent-capitalized
#                 phrase detection in Recommendation.top_phrases.
#                 INTENTIONALLY a much narrower subset of GENERAL:
#                 articles ("the", "an"), pronouns ("i", "we"),
#                 interrogatives ("what", "where"), conjunctions
#                 ("if", "and"). Words like "new" / "north" / "first"
#                 are in GENERAL (we don't want them as unigram
#                 topics) but are NOT in PHRASE because they ARE
#                 legitimate first words of proper-noun phrases —
#                 "New York", "North Dakota", "First Republic". ~24
#                 words.
#   * CATEGORY  — small explicit filter for publisher-supplied
#                 category tags that are global brand noise rather
#                 than per-article topics (NPR puts "News" on every
#                 entry). The TopicClusters ubiquity ceiling catches
#                 these dynamically once the corpus is large enough
#                 (≥20 articles), but this explicit list also catches
#                 them on tiny windows and is greppable when a new
#                 offender shows up. ~14 words.
#
# All three are Sets so include? is O(1). Frozen so a caller can't
# mutate the list and silently degrade another caller's behavior.
#
# Stopwords are version-controlled (this file) because they change
# rarely and need code review when they do — a too-broad word here
# can nuke a legitimate cluster. STUFF #28.1 reviewed this decision
# vs. a YAML/JSON config or a DB table; the answer was "keep here."
module Stopwords
  # Common English + site/social/URL boilerplate. Used by:
  #   * Summarizer::Extractive — drops these from the term distribution
  #     used to score sentences for the extractive summary.
  #   * Recommendation.top_keywords — drops these from the body-token
  #     keyword list that feeds /article recommendations + /topics.
  GENERAL = %w[
    a about above after again against all am an and any are aren as at
    be because been before being below between both but by could
    did didn do does doesn doing don down during each
    few for from further had hadn has hasn have haven having he her here
    hers herself him himself his how i if in into is isn it its itself
    just like
    ll m me might more most mustn my myself
    no nor not now
    of off on once only or other our ours ourselves out over own
    re s same shan she should shouldn so some such
    t than that the their theirs them themselves then there these they
    this those through to too
    under until up
    ve very
    was wasn we were weren what when where which while who whom why will with won would
    y you your yours yourself yourselves

    can cant cannot could couldnt may might must shall should would
    get gets getting got gotten go goes going gone went
    make makes made making take takes took taken taking
    see saw seen seeing know knew known knowing think thinks thought thinking
    say says said saying tell tells told telling ask asks asked asking
    come comes came coming put puts putting find finds found finding
    give gives gave given giving look looks looked looking
    want wants wanted wanting need needs needed
    seem seems seemed feel feels felt
    use uses used using try tries tried trying
    keep keeps kept work works worked working
    let lets letting

    one two three four five six seven eight nine ten
    first second third last next previous new old
    good bad great better best worse worst big small large
    lot lots many much some any few several
    thing things stuff something anything everything nothing
    way ways part parts kind kinds sort sorts type types
    number percent rest

    today yesterday tomorrow now then later soon recently currently
    day days week weeks month months year years time times moment moments
    morning afternoon evening night tonight
    always never often sometimes usually still already yet ever
    back here there everywhere anywhere somewhere

    also just even well around since though although while because however
    really very pretty quite rather actually probably maybe perhaps
    basically literally essentially mostly mainly especially generally
    simply almost nearly close enough either neither both each every
    via according per among across through within without

    read reading reader page pages site sites article articles post posts
    story stories piece pieces blog blogs comment comments share shares
    subscribe subscriber subscribers newsletter newsletters
    follow follows follower followers
    click clicks tap taps link links url urls
    home menu nav footer header sidebar
    copyright reserved rights license terms privacy policy
    twitter facebook instagram tiktok youtube linkedin reddit threads bluesky
    whatsapp telegram discord slack
    photo photos picture pictures image images video videos clip clips

    com org net io co gov edu www http https html htm xml json
    utm src ref href

    mr mrs ms dr prof
    monday tuesday wednesday thursday friday saturday sunday
    january february march april may june july august september october november december
    jan feb mar apr jun jul aug sep sept oct nov dec

    end ends ending start starts starting
    open opens close closes closing
    add adds added adding remove removes removed removing
    show shows showed shown showing hide hides hidden hiding
    help helps helped helping support supports supported
    include includes included including
  ].to_set.freeze

  # Narrower than GENERAL — used ONLY by Recommendation.top_phrases
  # to reject bigram candidates whose first or second word is a
  # sentence-initial false-positive ("The President", "What Trump said").
  # Critically does NOT include "new" / "north" / "first" — those are
  # valid proper-noun phrase prefixes.
  PHRASE = %w[
    the a an this that these those
    i you he she we they it
    what when where which who whom why how
    if and but or so
    mr mrs ms dr prof
  ].to_set.freeze

  # Publisher category-tag brand noise. Used by TopicClusters.parse_categories.
  CATEGORY = %w[
    news article articles post posts story stories blog blogs feed feeds
    general latest update updates featured uncategorized misc miscellaneous
  ].to_set.freeze
end
