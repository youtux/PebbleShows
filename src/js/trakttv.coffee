ajax = require('ajax')
Settings = require('settings')
Emitter = require('emitter')

async = require('async')

trakttv = {}

events = new Emitter()
shows = Settings.data 'shows'

trakttv.on = (args...) -> events.on(args...)

trakttv.request = (opt, success, failure) ->
  console.log "trakttv.request: opt: #{JSON.stringify opt}"
  # console.log success
  if typeof opt == 'string'
    opt = if opt.indexOf('http') == 0
      url: opt
    else
      action: opt

  opt.method ?= 'GET'

  if opt.action[0] == '/'
    opt.action = opt.action[1..]

  opt.url ?= "http://api-v2launch.trakt.tv/#{opt.action}"

  accessToken = Settings.option 'accessToken'
  unless accessToken?
    events.emit 'authorizationRequired', 'Missing access token'

  ajax
    url: opt.url
    type: 'json'
    headers:
      'trakt-api-version': 2
      'trakt-api-key': '16fc8c04f10ebdf6074611891c7ce2727b4fcae3d2ab2df177625989543085e9'
      Authorization: "Bearer #{accessToken}"
    method: opt.method
    data: opt.data
    success
    (response, status, req) ->
      if status == 401
        console.log "Server says that authorization is required"
        events.emit 'authorizationRequired', 'Authorization required from server'
      console.log "Request failure (#{status} #{opt.method} #{opt.url})"
      failure? response, status, req

trakttv.refreshModels = (cb) ->
  console.log "refreshing models"
  trakttv.request '/sync/watched/shows', (response, status, req) ->
    # console.log "Returned shows: #{JSON.stringify shows.map (e)->e.show}"
    shows = response
    Settings.data shows: shows
    trakttv.getToWatchList response, cb

trakttv.getToWatchList = (callback) ->
  async.each(
    shows,
    (item, doneItem) ->
      trakttv.request "/shows/#{item.show.ids.trakt}/progress/watched",
        (response, status, req) ->
          # console.log "returned: #{JSON.stringify response.seasons}"
          item.next_episode = response.next_episode
          item.seasons = response.seasons
          Settings.data shows: shows

          events.emit 'update', 'show', item

          # for season in item.seasons
          #   for episode in season.episodes
          #     episode.completed ?= false
          doneItem()

        (response, status, req) ->
          doneItem()
    (err) ->
      events.emit 'update', 'shows', shows
      callback? shows
  )


trakttv.reloadShow = (showID, success, failure) ->
  trakttv.request "/shows/#{showID}/progress/watched",
    (response, status, req) ->
      console.log "Reloading show #{showID}"
      # console.log "response: #{JSON.stringify response}"
      item = i for i in shows when i.show.ids.trakt == showID

      item.next_episode = response.next_episode
      item.seasons = response.seasons
      Settings.data shows: shows
      success? item
    failure

trakttv.getOrFetchEpisodeData = (showID, seasonNumber, episodeNumber, callback) ->
  # toWatchMenu.on 'select', (e) ->
  # element = e.item
  # console.log "getOrFetchEpisodeData for #{showID}, #{seasonNumber}, #{episodeNumber}"
  item = i for i in shows when i.show.ids.trakt == showID
  # console.log "item: #{JSON.stringify item}"
  season = s for s in item.seasons when s.number == seasonNumber
  unless season?
    season =
      number: seasonNumber
      aired: 0
      completed: 0
      episodes: []
  # console.log "season: #{JSON.stringify season}"
  episode = e for e in season.episodes when e.number == episodeNumber
  # console.log "episode: #{JSON.stringify episode}"
  unless episode?
    episode =
      number: episodeNumber
      completed: false
    season.episodes.push episode
  # console.log "Considering episode: #{JSON.stringify episode}"

  episode.seasonNumber = seasonNumber
  episode.episodeNumber = episodeNumber
  episode.showID = showID
  episode.showTitle = item.show.title

  getOrFetchOverview = (success) ->
    if episode.overview?
      # console.log "Overview already available"
      success(episode)
      return
    # console.log "fetching overview..."
    trakttv.request "/search?id_type=trakt-episode&id=#{episode.episodeID}",
      (response, status, req) ->
        # console.log "Fetched overview: #{response}"
        if response
          episode.overview = response[0].episode.overview
          Settings.data shows: shows
        success? episode

  fetchEpisodeIDAndTitle = (showID, seasonNumber, episodeNumber, successFetchEpisodeIDAndTitle) ->
    trakttv.request "/shows/#{showID}/seasons/#{seasonNumber}/episodes/#{episodeNumber}",
      (response, status, req) ->
        # console.log "fetchEpisodeIDAndTitle response: #{response}"
        episode.episodeID = response.ids.trakt
        episode.episodeTitle = response.title
        Settings.data shows: shows

        successFetchEpisodeIDAndTitle(episode) if successFetchEpisodeIDAndTitle?

  if episode.episodeID? and episode.episodeTitle?
    # console.log "going to fetch overview"
    getOrFetchOverview callback
  else
    # console.log "going to fetch ep id and title"
    fetchEpisodeIDAndTitle showID, seasonNumber, episodeNumber,
      (episode) ->
        # console.log "fetched id and title: #{JSON.stringify episode}"
        getOrFetchOverview callback

module.exports = trakttv
