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
    events.emit 'authorizationRequired', message: 'Missing access token'

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
        events.emit 'authorizationRequired', message: 'Authorization required from server'
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

            events.emit 'update', 'show', show: item

            doneItem()
          (status) ->
            console.log "Failed: #{status}"
            doneItem()
      (err) ->
        events.emit 'update', 'shows', shows: shows
        cb? err, shows
    )

trakttv.getCalendar = (fromDate, daysWindow, cb) ->
  trakttv.request "/calendars/shows/#{fromDate}/#{daysWindow}",
    (response, status, req) =>
      events.emit 'update', 'calendar', calendar: response
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

# {
#   season: 1,
#   number: 1,
#   title: "Pilot",
#   episodeID: 73482,
#   overview: "When an unassuming high school chemistry teacher discovers he has a rare form of lung cancer, he decides to team up with a former student and create a top of the line crystal meth in a used RV, to provide for his family once he is gone.",
#   images: {
#     screenshots: {
#       full: "https://walter.trakt.us/images/episodes/000/073/482/screenshots/original/ef3352bcb8.jpg",
#       medium: "https://walter.trakt.us/images/episodes/000/073/482/screenshots/medium/ef3352bcb8.jpg",
#       thumb: "https://walter.trakt.us/images/episodes/000/073/482/screenshots/thumb/ef3352bcb8.jpg"
#     }
#   },
#   show: {
#     title: "Breaking Bad",
#     year: "2008",
#     showID: 1388
#   }
# }
trakttv.getEpisodeData = (showID, seasonNumber, episodeNumber, callback) ->
  result = {}
# {
#   "season":1,
#   "number":1,
#   "title":"Pilot",
#   "ids":{
#     "trakt":73482,
#     "tvdb":349232,
#     "imdb":"tt0959621",
#     "tmdb":62085,
#     "tvrage":637041
#   }
# }
  trakttv.request "/shows/#{showID}/seasons/#{seasonNumber}/episodes/#{episodeNumber}",
    (response, status, req) ->
      console.log "fetch episode id and title response: #{JSON.stringify response}"
      result.title = response.title
      result.episodeID = episodeID = response.ids.trakt
      result.season = response.season
      result.number = response.number

      trakttv.searchEpisode episodeID, (err, response) ->
        return callback(err) if err?

        result.overview = response.episode.overview
        result.images = response.episode.images

        result.show =
          title: response.show.title
          showID: response.show.ids.trakt

        events.emit 'update', 'episode', episode: result

        callback null, result
    (response, status, req) ->
      callback status

#   {
#     "type":"episode",
#     "score":null,
#     "episode":{
#       "season":1,
#       "number":1,
#       "title":"Pilot",
#       "overview":"When an unassuming high school chemistry teacher discovers he has a rare form of lung cancer, he decides to team up with a former student and create a top of the line crystal meth in a used RV, to provide for his family once he is gone.",
#       "images":{
#         "screenshot":{
#           "full":"https://walter.trakt.us/images/episodes/000/073/482/screenshots/original/ef3352bcb8.jpg",
#           "medium":"https://walter.trakt.us/images/episodes/000/073/482/screenshots/medium/ef3352bcb8.jpg",
#           "thumb":"https://walter.trakt.us/images/episodes/000/073/482/screenshots/thumb/ef3352bcb8.jpg"
#         }
#       },
#       "ids":{
#         "trakt":73482,
#         "tvdb":349232,
#         "imdb":"tt0959621",
#         "tmdb":62085,
#         "tvrage":637041
#       }
#     },
#     "show":{
#       "title":"Breaking Bad",
#       "year":"2008",
#       "ids":{
#         "trakt":1388,
#         "slug":"breaking-bad"
#       },
#       "images":{
#         "poster":{
#           "full":"https://walter.trakt.us/images/shows/000/001/388/posters/original/fa39b59954.jpg",
#           "medium":"https://walter.trakt.us/images/shows/000/001/388/posters/medium/fa39b59954.jpg",
#           "thumb":"https://walter.trakt.us/images/shows/000/001/388/posters/thumb/fa39b59954.jpg"
#         },
#         "fanart":{
#           "full":null,
#           "medium":"https://walter.trakt.us/images/shows/000/001/388/fanarts/medium/fdbc0cb02d.jpg",
#           "thumb":"https://walter.trakt.us/images/shows/000/001/388/fanarts/thumb/fdbc0cb02d.jpg"
#         }
#       }
#     }
#   }
trakttv.searchEpisode = (episodeID, cb) ->
  trakttv.request "/search?id_type=trakt-episode&id=#{episodeID}",
    (response, status, req) ->
      cb null, response[0]
    (response, status, req) ->
      cb status

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

trakttv.modifyEpisodeCheckState = (showID, seasonNumber, episodeNumber, state, cb) ->
  request =
    shows: [
      ids: trakt: showID
      seasons: [{
        number: seasonNumber
        episodes: [{
          number: episodeNumber
        }]
      }]
    ]

  action =
    if state == 'check'
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
      # for item in shows when item.show.ids.trakt == showID
      #   for season in item.seasons when not seasonNumber? or season.number == seasonNumber
      #     for episode in season.episodes when not episodeNumber? or episode.number == episodeNumber
      #       episode.completed = completed
      #       console.log "Marking as seen #{item.show.title} S#{season.number}E#{episode.number}, #{episode.completed}"
      cb null
    (response, status, req) ->
      console.log "Check FAILURE"
      cb status

trakttv.checkEpisode = (showID, seasonNumber, episodeNumber, cb) ->
  trakttv.modifyEpisodeCheckState showID, seasonNumber, episodeNumber, 'check', cb

trakttv.uncheckEpisode = (showID, seasonNumber, episodeNumber, cb) ->
  trakttv.modifyEpisodeCheckState showID, seasonNumber, episodeNumber, 'uncheck', cb

module.exports = trakttv
