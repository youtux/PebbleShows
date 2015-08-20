config = require('config')

ajax = require('ajax')
Settings = require('settings')
Emitter = require('emitter')
async = require('async')
appinfo = require('appinfo')

events = new Emitter()

merge = (objects...) ->
  res = {}
  for obj in objects
    for key, value of obj
       res[key] = value
  res

uniqBy = (arr, key) ->
    seen = {}
    arr.filter (item)->
      k = key(item)
      if seen.hasOwnProperty(k)
        false
      else
        seen[k] = true
        true

trakttv = {}

trakttv.BASE_URL = 'https://api-v2launch.trakt.tv'

trakttv.on = (args...) -> events.on(args...)

trakttv.request = (opt, callback) ->
  console.log "trakttv.request: opt: #{JSON.stringify opt}"
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
    (response, status, req) =>
      callback null, response
    (response, status, req) ->
      console.log "Request failure (#{status} #{opt.method} #{opt.url})"
      if status == 401
        console.log "Server says that authorization is required"
        events.emit 'authorizationRequired', message: 'Authorization required from server'
        return

      if status == null
        err = new Error("Connection not available.")
      else
        err = new Error("Communication error (#{status}).")

      callback err


trakttv.getWatched = (callback) ->
  trakttv.request '/sync/watched/shows', callback

trakttv.getWatchList = (callback) ->
  trakttv.request '/sync/watchlist/shows', callback


trakttv.fetchToWatchList = (callback) ->
  async.parallel(
    watched: trakttv.getWatched
    watchlist: trakttv.getWatchList
    (err, result) =>
      return callback(err) if err?

      shows = uniqBy(
        Array::concat(result.watchlist, result.watched)
        (elem) -> elem.show.ids.trakt
      )

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
              doneItem()
        (err) ->
          events.emit 'update', 'shows', shows: shows
          callback err, shows
      )
  )

trakttv.getCalendar = (fromDate, daysWindow, callback) ->
  trakttv.request "/calendars/shows/#{fromDate}/#{daysWindow}",
    (err, response) =>
      return callback(err) if err?

      events.emit 'update', 'calendar', calendar: response
      callback null, response

trakttv.fetchShowProgress = (showID, callback) ->
  trakttv.request "/shows/#{showID}/progress/watched", callback

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
    (err, response) =>
      return callback(err) if err?

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
trakttv.searchEpisode = (episodeID, callback) ->
  trakttv.request "/search?id_type=trakt-episode&id=#{episodeID}",
    (err, response) =>
      return callback(err) if err?

      callback null, response[0]

trakttv.markEpisode = (episodeObj, seen, watched_at, callback) ->
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
    callback

trakttv.checkInEpisode = (episodeObj, callback) ->
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
    callback

trakttv.modifyEpisodeCheckState = (showID, seasonNumber, episodeNumber, state, callback) ->
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

  trakttv.request
    action: action
    method: 'POST'
    data: request
    (err, response) =>
      return callback(err) if err?

      callback null

trakttv.checkEpisode = (showID, seasonNumber, episodeNumber, callback) ->
  trakttv.modifyEpisodeCheckState showID, seasonNumber, episodeNumber, 'check', callback

trakttv.uncheckEpisode = (showID, seasonNumber, episodeNumber, callback) ->
  trakttv.modifyEpisodeCheckState showID, seasonNumber, episodeNumber, 'uncheck', callback

module.exports = trakttv
