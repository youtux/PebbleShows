UI = require('ui')
Settings = require('settings')
ajax = require('ajax')
async = require('async')
require 'Object.observe.poly'

console.log "accessToken: #{Settings.option 'accessToken'}"
mainMenu = undefined
signInWindow = undefined

model =
  watchedShows: undefined
  toWatchList: undefined

WATCHED_URL = 'https://api-v2launch.trakt.tv/users/me/watched/shows'

getWatchedShows = (callback) ->
  # TODO: use watchlist too
  traktvRequest WATCHED_URL, (response, status, req) ->
    callback response.map (show_detailed) -> show_detailed.show



###
[{
    "completed": false,
    "show": {...},
    "season": 1,
    "episode": 5,
  }, ...]
###

getToWatchList = (callback) ->
  episodeList = []
  async.each(
    model.watchedShows
    (item, doneItem) ->
      show = item
      traktvRequest(
        "https://api-v2launch.trakt.tv/shows/#{show.ids.trakt}/progress/watched"
        (response, status, req) ->
          if status != 200
            doneItem(response: response, status: status, req: req)
          for season in response.seasons
            for episode in season.episodes
              if episode.completed
                continue
              episodeList.push
                completed: episode.completed
                show: show
                season: season.number
                episode: episode.number
          doneItem()
      )
    (err) ->
      if err?
        console.log "Failed response (#{err.status}): #{err.response}"
        console.log "Request was: #{err.req}"
      callback(episodeList)
  )

displaySignInWindow = ->
  signInWindow = new UI.Card(
    title: 'Sign-in required'
    body: 'Open the Pebble App and configure Pebble Shows.'
  )
  signInWindow.on 'click', 'back', ->
    # No escape :)
    return
  signInWindow.show()
  return

refreshModels = ->
  getWatchedShows (_watchedShows) ->
    console.log "Returned watchedShows: #{JSON.stringify _watchedShows}"
    model.watchedShows = _watchedShows
    getToWatchList (_toWatchList) ->
      console.log 'toWatchList updated: ' + JSON.stringify _toWatchList
      model.toWatchList = _toWatchList

checkWatched = (episode) ->
  console.log("Check watched! episode: #{JSON.stringify(episode)}")
  request =
    shows: [
      episode.show
      seasons: [
        number: episode.season
        episodes: [
          number: episode.episode
        ]
      ]
    ]
  console.log "request: #{JSON.stringify request}"
  traktvRequest
    url: 'https://api-v2launch.trakt.tv/sync/history'
    method: 'POST'
    data: request
    (response, status, req) -> console.log "Check SUCCESS"

displayToWatchMenu = ->
  unless model.toWatchList?
    observer = (changes) ->
      unless 'toWatchList' in (change.name for change in changes)
        return

      console.log 'called observe. this is ', JSON.stringify(this)
      displayToWatchMenu()
      Object.unobserve model.toWatchList, observer

    Object.observe model, observer
    return;
  items = []
  console.log 'displayToWatchMenu: toWatchList: ', JSON.stringify(model.toWatchList)
  for ep in model.toWatchList
    console.log "considering: " + JSON.stringify(ep)
    items.push
      title: ep.show.title
      subtitle: 'Season ' + ep.season + ' Ep. ' + ep.episode
      episode: ep

  console.log 'obtained items: ', JSON.stringify(items)
  toWatchMenu = new (UI.Menu)(sections: [ { 'items': items } ])
  toWatchMenu.on 'longSelect', (e) ->
    checkWatched(e.item.episode)
  toWatchMenu.on 'select', (e) ->
    episode = e.item.episode
    traktvRequest(
      "https://api-v2launch.trakt.tv/shows/#{episode.show.id}/seasons/#{episode.season}/episodes/#{episode.episode}",
      (response, status, req) ->
        # response = {
        #   "season": 1,
        #   "number": 1,
        #   "title": "Winter Is Coming",
        #   "ids": {
        #     "trakt": 36440,
        #     "tvdb": 3254641,
        #     "imdb": "tt1480055",
        #     "tmdb": 63056,
        #     "tvrage": null
        #   }
        # }
        detailedItem = new UI.Card(
          title: episode.show.title
          subtitle: "Season #{episode.season} Ep. #{episode.episode}"
          body: "Title: #{response.title}"
          style: 'small'
        )
        detailedItem.on('longClick', 'select', ->
          detailedItem.hide()
          checkWatched(episode)
        )
        detailedItem.show()
    )
  toWatchMenu.show()
  return

CONFIG_BASE_URL = 'http://bobby.alessiobogon.com:8020/'
WATCHED_URL = 'https://api-v2launch.trakt.tv/users/me/watched/shows'
signInWindow = undefined
mainMenu = undefined

###
[{
  title: "abc",
  year: 2014,
  id: 1234
}, ...]
###

traktvRequest = (opt, success, failure) ->
  console.log "traktvRequest: opt: #{JSON.stringify opt}"
  if typeof opt == 'string'
    opt = if opt.indexOf('http') == 0
      url: opt
    else
      action: opt

  method = opt.method ? 'GET'

  url = if opt.url
    opt.url
  else
    if opt.action[0] != '/'
      opt.action = '/' + opt.action
    "https://api-v2launch.trakt.tv" : opt.action

  data = opt.data

  accessToken = Settings.option 'accessToken'
  unless accessToken?
    displaySignInWindow()
    return

  ajax
    url: url
    type: 'json'
    headers:
      'trakt-api-version': 2
      'trakt-api-key': '16fc8c04f10ebdf6074611891c7ce2727b4fcae3d2ab2df177625989543085e9'
      Authorization: 'Bearer ' + accessToken
    method: method ? 'GET'
    data: data
    success
    (body, status, req) ->
      if status == 401
        console.log "Server says that authorization is required"
        displaySignInWindow()
      failure(body, status, req)


# Set a configurable with the open callback
Settings.config {
  url: CONFIG_BASE_URL
  autoSave: true
}, (e) ->
  signInWindow.hide()
  refreshModels()
  return

###
// Show splash screen while waiting for data
var splashWindow = new UI.Card({
  title: 'Pebble Shows',
  icon: 'images/menu_icon.png',
  subtitle: 'The shows on your Pebble!',
  body: 'Connecting...'
});
splashWindow.show();
###

mainMenu = new UI.Menu
  sections: [
    items: [{
      title: 'To watch'
      id: 'toWatch'
    },{
      title: 'Calendar'
      id: 'calendar'
    }]
  ]

mainMenu.on 'select', (e) ->
  switch e.item.id
    when 'toWatch'
        displayToWatchMenu()



if PEBBLE_DEVELOPER?
  newSectionIndex = mainMenu.state.sections.length
  mainMenu.items newSectionIndex, [
    title: 'Developer tools'
    id: 'developer'
  ]
  mainMenu.on 'select', (e) ->
    switch e.item.id
      when 'developer'
        devMenu = new UI.Menu
          sections: [
            items: [{
              title: 'Reset localStorage'
              action: localStorage.clear()
            }, {
              title: 'SAY MY NAME!'
              action: -> console.log 'YOU\'RE HEISENBERG'
            }]
          ]

        devMenu.on 'select', (e) -> e.item.action()
        devMenu.show()

mainMenu.show()
refreshModels()

console.log "PEBBLE_DEVELOPER: " + typeof PEBBLE_DEVELOPER

