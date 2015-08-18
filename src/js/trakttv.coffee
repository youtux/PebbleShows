config = require('config')

ajax = require('ajax')
Settings = require('settings')
Emitter = require('emitter')
async = require('async')
appinfo = require('appinfo')

shows = Settings.data 'shows'
events = new Emitter()

trakttv = {}

trakttv.BASE_URL = 'https://api-v2launch.trakt.tv'

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

  opt.url ?= "#{trakttv.BASE_URL}/#{opt.action}"

  accessToken = Settings.option 'accessToken'
  unless accessToken?
    events.emit 'authorizationRequired', 'Missing access token'

  ajax
    url: opt.url
    type: 'json'
    headers:
      'trakt-api-version': 2
      'trakt-api-key': config.TRAKT_CLIENT_ID
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


trakttv.getShows = (cb) ->
  trakttv.request '/sync/watched/shows',
    (response, status, req) ->
      # console.log "Returned shows: #{JSON.stringify shows.map (e)->e.show}"
      # trakttv.getToWatchList response, cb
      cb(null, response)
    (response, status, req) ->
      cb(status)


trakttv.fetchToWatchList = (cb) ->
  trakttv.getShows (err, shows) ->
    # TODO: Check err
    return if err?

    async.each(
      shows,
      (item, doneItem) ->
        showID = item.show.ids.trakt
        trakttv.fetchShowProgress showID,
          (err, showProgress) ->
            return doneItem() if err?

            item = i for i in shows when i.show.ids.trakt == showID

            item.next_episode = showProgress.next_episode
            item.seasons = showProgress.seasons

            events.emit 'update', 'show', item

            doneItem()
          (status) ->
            console.log "Failed: #{status}"
            doneItem()
      (err) ->
        events.emit 'update', 'shows', shows
        cb? err, shows
    )

trakttv.getCalendar = (fromDate, daysWindow, cb) ->
  trakttv.request "/calendars/shows/#{fromDate}/#{daysWindow}",
    (response, status, req) =>
      events.emit 'update', 'calendar', response
      cb?(null, response)
    (response, status, req) =>
      console.log "Failed to fetch the calendar"
      cb?(status)

trakttv.fetchShowProgress = (showID, cb) ->
  trakttv.request "/shows/#{showID}/progress/watched",
    (response, status, req) ->
      cb(null, response)
    (response, status, req) ->
      cb(status)

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

trakttv.markEpisode = (episodeObj, seen, watched_at, cb) ->
  episode =
    if (typeof episodeObj) == 'number'
      {
        ids:
          trakt: episodeObj
      }
    else
      episodeObj

  # HACK: clone obj
  episode = JSON.parse(JSON.stringify(episode))
  episode.watched_at = watched_at

  action =
    if seen
      '/sync/history'
    else
      '/sync/history/remove'

  body =
    episodes: [episode]

  @request
    action: action
    method: 'POST'
    data: body
    (data, status, req) ->
      cb(null, data)
    (err, status, req) ->
      cb(err, status, req)

trakttv.checkInEpisode = (episodeObj, cb) ->
  episode =
    if (typeof episodeObj) == 'number'
      {
        ids:
          trakt: episodeObj
      }
    else
      episodeObj

  # HACK: clone obj
  episode = JSON.parse(JSON.stringify(episode))

  @request
    action: '/checkin'
    method: 'POST'
    data:
      episode: episode
      app_version: appinfo.versionLabel
    (data, status, req) ->
      cb(null, data)
    (err, status, req) ->
      cb(err, status, req)

trakttv.modifyCheckState = (opt, success, failure) ->
  # console.log("Check watched! episode: #{JSON.stringify(episode)}")
  console.log "checkWatched: opt: #{JSON.stringify opt}"
  if opt.episodeNumber? and not opt.seasonNumber?
    throw new Error("Not enough data given: #{JSON.stringify opt}")
    return

  opt.completed ?= true

  request =
    shows: [
      ids: trakt: opt.showID
      seasons: [{
        number: opt.seasonNumber
        episodes: [{
          number: opt.episodeNumber
        }] if opt.episodeNumber
      }] if opt.seasonNumber
    ]

  action = if opt.completed
    '/sync/history'
  else
    '/sync/history/remove'

  console.log "request: POST #{action} params:#{JSON.stringify request}"
  trakttv.request
    action: action
    method: 'POST'
    data: request
    (response, status, req) ->
      console.log "Check succeeded: req: #{JSON.stringify request}"
      console.log "response: #{JSON.stringify response}"
      # console.log "#{index}: #{key}: #{value}" for key, value of index for index in shows
      for item in shows when item.show.ids.trakt == opt.showID
        for season in item.seasons when not opt.seasonNumber? or season.number == opt.seasonNumber
          for episode in season.episodes when not opt.episodeNumber? or episode.number == opt.episodeNumber
            episode.completed = opt.completed
            console.log "Marking as seen #{item.show.title} S#{season.number}E#{episode.number}, #{episode.completed}"
      success()
    (response, status, req) ->
      console.log "Check FAILURE"
      failure(response, status, req)

module.exports = trakttv
