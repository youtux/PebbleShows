UI = require('ui')
Settings = require('settings')
ajax = require('ajax')
async = require('async')
require 'Object.observe.poly'

CONFIG_BASE_URL = 'http://bobby.alessiobogon.com:8020/'

console.log "accessToken: #{Settings.option 'accessToken'}"

mainMenu = undefined
signInWindow = undefined
detailedItemCard = undefined
mainMenu = undefined

model =
  shows: undefined


getToWatchList = (showList, callback) ->
  showListUpdated = showList[..]
  async.each(
    showListUpdated
    (item, doneItem) ->
      traktvRequest(
        "https://api-v2launch.trakt.tv/shows/#{item.show.ids.trakt}/progress/watched"
        (response, status, req) ->
          # console.log "getToWatchList: asked "
          # console.log "returned: #{JSON.stringify response.seasons}"
          if status != 200
            doneItem(response: response, status: status, req: req)
          item.next_episode = response.next_episode
          item.seasons = response.seasons
          for season in item.seasons
            for episode in season.episodes
              episode.completed ?= false
          doneItem()
      )
    (err) ->
      if err?
        console.log "Failed response (#{err.status}): #{err.response}"
        console.log "Request was: #{err.req}"
      console.log "getToWatchList returning"
      callback(showListUpdated)
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
 traktvRequest 'sync/watched/shows', (response, status, req) ->
    shows = response
    # console.log "Returned shows: #{JSON.stringify shows.map (e)->e.show}"
    getToWatchList shows, (toWatchList) ->
      console.log 'toWatchList updated'
      model.shows = toWatchList

checkWatched = (episode, success, failure) ->
  # console.log("Check watched! episode: #{JSON.stringify(episode)}")
  request =
    shows: [
      title: episode.show.title
      year: episode.show.year
      ids: episode.show.ids
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
    (response, status, req) ->
      console.log "Check SUCCESS"
      # console.log "#{index}: #{key}: #{value}" for key, value of index for index in model.shows
      itemToMark = item for item in model.shows when item.show.ids.trakt == episode.show.ids.trakt
      seasonToMark = season for season in itemToMark.seasons when season.number == episode.season
      console.log "season to mark: #{JSON.stringify seasonToMark}"
      episodeToMark = ep for ep in seasonToMark.episodes when ep.number == episode.episode
      console.log "ep to mark: #{JSON.stringify episodeToMark}"
      episodeToMark.completed = true
      # console.log "found show. #{key}, #{value}" for key, value of show
      # console.log "I must update loca show #{show.title}"
      success()
    (response, status, req) ->
      console.log "Check FAILURE"
      failure(response, status, req)


compareByKey = (key) ->
  (a, b) ->
    -1 if a[key] < b[key]
    0 if a[key] == b[key]
    1 if a[key] > b[key]

# {
#   episode: 12
#   season: 2
# } or undefined
firstUnwatchedEpisode = (show) ->
  seasons = show.seasons[..]
  seasons.sort compareByKey('number')
  for season in seasons
    # console.log "considering #{JSON.stringify season}"
    episodes = season.episodes[..]
    episodes.sort(compareByKey('number'))
    for episode in episodes
      unless episode.completed
        return {
          episode: episode.number
          season: season.number
        }


displayToWatchMenu = ->
  unless model.shows?
    observer = (changes) ->
      unless 'shows' in (change.name for change in changes)
        return

      console.log 'called observe. this is ', JSON.stringify(this)
      displayToWatchMenu()
      Object.unobserve model.shows, observer

    Object.observe model, observer
    return;

  getToWatchMenuItems = ->
    toWatch = []
    for item in model.shows
      # console.log "Title: #{item.show.title}"
      ep = firstUnwatchedEpisode(item)
      # console.log "firstUnwatchedEpisode: #{JSON.stringify ep}}"
      if ep?
        toWatch.push
          title: item.show.title
          subtitle: "Season #{ep.season} Ep. #{ep.episode}"
          data:
            episode: ep.episode
            season: ep.season
            show: item.show
    toWatch

  toWatchMenu = new UI.Menu(
    sections: [{
      items: getToWatchMenuItems()
      }]
    )
  checkHandler = (e) ->
    console.log "Deleting menu item [#{e.sectionIndex}, #{e.itemIndex}]"
    toWatchMenu.items(0, getToWatchMenuItems())

  toWatchMenu.on 'longSelect', (e) ->
    e.item.subtitle = "Checking in..."
    toWatchMenu.item(e.sectionIndex, e.itemIndex, e.item)
    checkWatched e.item.data, ->
      console.log "End of checkWatched. needt to remove"
      console.log "#{key}: #{value}" for key, value of e
      checkHandler(e)

  toWatchMenu.on 'select', (e) ->
    episode = e.item.data
    traktvRequest(
      "https://api-v2launch.trakt.tv/shows/#{episode.show.ids.trakt}/seasons/#{episode.season}/episodes/#{episode.episode}",
      (response, status, req) ->
        detailedItemCard = new UI.Card(
          title: episode.show.title
          subtitle: "Season #{episode.season} Ep. #{episode.episode}"
          body: "Title: #{response.title}"
          style: 'small'
        )
        detailedItemCard.on('longClick', 'select', ->
          e.item.subtitle = "Checking in..."
          toWatchMenu.item(e.sectionIndex, e.itemIndex, e.item)
          detailedItemCard.hide()
          checkWatched episode, -> checkHandler(e)
        )
        detailedItemCard.show()
    )
  toWatchMenu.show()
  return

traktvRequest = (opt, success, failure) ->
  console.log "traktvRequest: opt: #{JSON.stringify opt}"
  # console.log success
  if typeof opt == 'string'
    opt = if opt.indexOf('http') == 0
      url: opt
    else
      action: opt

  method = opt.method ? 'GET'

  url = if opt.url
    opt.url
  else
    if opt.action[0] == '/'
      opt.action = opt.action[1..]
    "https://api-v2launch.trakt.tv/#{opt.action}"

  # console.log "build url: " + JSON.stringify(url)

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
      Authorization: "Bearer #{accessToken}"
    method: method
    data: data
    success
    (response, status, req) ->
      if status == 401
        console.log "Server says that authorization is required"
        displaySignInWindow()
      console.log "Request failure (#{status} #{method} #{url})"
      failure(response, status, req)


# Set a configurable with the open callback
Settings.config {
  url: CONFIG_BASE_URL
  autoSave: true
}, (e) ->
  signInWindow.hide()
  refreshModels()

refreshModels()

mainMenu = new UI.Menu
  sections: [
    items: [{
      title: 'To watch'
      id: 'toWatch'
    },{
      title: 'Calendar'
      id: 'calendar'
    }, {
      title: 'Advanced'
      id: 'advanced'
    }]
  ]

mainMenu.on 'select', (e) ->
  switch e.item.id
    when 'toWatch'
      displayToWatchMenu()
    when 'advanced'
      advancedMenu = new UI.Menu
        sections: [
          items: [{
            title: 'Reset localStorage'
            action: -> localStorage.clear()
          }, {
            title: 'Refresh'
            action: -> refreshModels()
          }]
        ]
      advancedMenu.on 'select', (e) -> e.item.action()
      advancedMenu.show()

mainMenu.show()

