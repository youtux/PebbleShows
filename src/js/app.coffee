UI = require('ui')
Settings = require('settings')
ajax = require('ajax')
async = require('async')
Emitter = require('emitter')

CONFIG_BASE_URL = 'http://bobby.alessiobogon.com:8020/'
ICON_MENU_UNCHECKED = 'images/icon_menu_unchecked.png'
ICON_MENU_CHECKED = 'images/icon_menu_checked.png'

console.log "accessToken: #{Settings.option 'accessToken'}"

mainMenu = undefined
signInWindow = undefined
detailedItemCard = undefined

updatesEmitter = new Emitter()

shows = undefined

sleep = (ms) ->
  unixtime_ms = new Date().getTime();
  while(new Date().getTime() < unixtime_ms + ms)
    1


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

reloadShow = (showID, success, failure) ->
  traktvRequest(
    "https://api-v2launch.trakt.tv/shows/#{showID}/progress/watched"
    (response, status, req) ->
      console.log "Reloading show #{showID}"
      item = i for i in shows when i.show.ids.trakt == showID

      item.next_episode = response.next_episode
      item.seasons = response.seasons
      success(item) if success?
    failure if failure?
  )



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
          # for season in item.seasons
          #   for episode in season.episodes
          #     episode.completed ?= false
          doneItem()
      )
    (err) ->
      if err?
        console.log "Failed response (#{err.status}): #{err.response}"
        console.log "Request was: #{err.req}"
      # console.log "getToWatchList returning"
      callback(showListUpdated) if callback?
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

isNextEpisodeForItemAired = (item) ->
  return false unless item.next_episode?
  if item.next_episode.season > item.seasons.length
    return false
  season = s for s in item.seasons when s.number == item.next_episode.season
  if item.next_episode.number > season.aired
    return false
  true

refreshModels = ->
  traktvRequest 'sync/watched/shows', (response, status, req) ->
    # console.log "Returned shows: #{JSON.stringify shows.map (e)->e.show}"
    getToWatchList response, (toWatchList) ->
      console.log 'toWatchList updated'
      shows = toWatchList
      updatesEmitter.emit 'update', 'shows', shows

modifyCheckState = (opt, success, failure) ->
  # console.log("Check watched! episode: #{JSON.stringify(episode)}")
  console.log "checkWatched: opt: #{JSON.stringify opt}"
  if opt.episodeNumber? and not opt.seasonNumber?
    failure()
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

  url = 'https://api-v2launch.trakt.tv/sync/history'
  url += '/remove' if opt.completed == false

  # console.log "request: #{JSON.stringify request}"
  traktvRequest
    url: url
    method: 'POST'
    data: request
    (response, status, req) ->
      console.log "Check succeeded: #{JSON.stringify request}"
      # console.log "#{index}: #{key}: #{value}" for key, value of index for index in shows
      for item in shows when item.show.ids.trakt == opt.showID
        for season in item.seasons when not opt.seasonNumber? or season.number == opt.seasonNumber
          for episode in season.episodes when not opt.episodeNumber? or episode.number == opt.episodeNumber
            console.log "Marking as seen #{item.show.title} S#{season.number}E#{episode.number}"
            episode.completed = opt.completed
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
    # console.log "considering #{show.show.title}, #{JSON.stringify seasons}"
    episodes = season.episodes[..]
    episodes.sort(compareByKey('number'))
    for episode in episodes
      unless episode.completed == true
        return {
          episodeNumber: episode.number
          seasonNumber: season.number
        }


displayToWatchMenu = (callback) ->
  unless shows?
    handler = (e) ->
      updatesEmitter.off 'updates', 'shows', handler
      displayToWatchMenu()
    updatesEmitter.on 'update', 'shows', handler
    return

  getToWatchMenuItems = ->
    toWatch = []
    for item in shows
      # console.log "Title: #{item.show.title}"
      ep = firstUnwatchedEpisode(item)
      ep_s = if ep? then "S#{ep.seasonNumber}E#{ep.episodeNumber}" else "undefined"
      console.log "First unwatched episode for #{item.show.title} is #{ep_s}"
      # console.log "firstUnwatchedEpisode: #{JSON.stringify ep}}"
      if ep?
        toWatch.push
          title: item.show.title
          subtitle: "Season #{ep.seasonNumber} Ep. #{ep.episodeNumber}"
          icon: ICON_MENU_UNCHECKED
          data:
            episodeNumber: ep.episodeNumber
            seasonNumber: ep.seasonNumber
            showID: item.show.ids.trakt
    toWatch

  # console.log "item: #{key}: #{value}" for key, value of item for item in shows
  # console.log "data: #{JSON.stringify data}"
  createToWatchMenuItem = (opt) ->
    for key in ['showID', 'episodeTitle', 'seasonNumber', 'episodeNumber', 'completed']
      unless opt[key]?
        console.log "ERROR: #{key} not in #{JSON.stringify opt}"
        return
    {
      title: opt.episodeTitle
      subtitle: "Season #{opt.seasonNumber} Ep. #{opt.episodeNumber}"
      icon: if opt.completed then ICON_MENU_CHECKED else ICON_MENU_UNCHECKED
      data:
        showID: opt.showID
        episodeNumber: opt.episodeNumber
        seasonNumber: opt.seasonNumber
        completed: opt.completed
        isNextEpisodeListed: opt.isNextEpisodeListed
    }

  toWatchMenu = new UI.Menu
    sections:
      {
        title: item.show.title
        items: [
          createToWatchMenuItem(
            showID: item.show.ids.trakt
            episodeTitle: item.next_episode.title
            seasonNumber: item.next_episode.season
            episodeNumber: item.next_episode.number
            completed: false
          )
        ]
      } for item in shows when isNextEpisodeForItemAired(item)

  toWatchMenu.on 'longSelect', (e) ->
    data = e.item.data
    modifyCheckState
      showID: data.showID
      episodeNumber: data.episodeNumber
      seasonNumber: data.seasonNumber
      completed: not e.item.completed
      () ->
        element = e.item
        isNowCompleted = not element.data.completed

        if isNowCompleted
          element.data.completed = true
          element.icon = ICON_MENU_CHECKED
        else
          element.data.completed = false
          element.icon = ICON_MENU_UNCHECKED

        toWatchMenu.item(e.sectionIndex, e.itemIndex, element)

        if isNowCompleted and not element.isNextEpisodeListed
          reloadShow data.showID, (reloadedShow) ->
            console.log "RELOADED ShowID: #{reloadedShow.show.ids.trakt}, title: #{reloadedShow.show.title}"
            if isNextEpisodeForItemAired(reloadedShow) and not element.isNextEpisodeListed
              element.isNextEpisodeListed = true

              newItem = createToWatchMenuItem(
                showID: data.showID
                episodeTitle: reloadedShow.next_episode.title
                seasonNumber: reloadedShow.next_episode.season
                episodeNumber: reloadedShow.next_episode.number
                completed: false
              )
              console.log "toWatchMenu.item(#{e.sectionIndex}, #{e.section.items.length}, #{JSON.stringify newItem}"

              toWatchMenu.item(e.sectionIndex, e.section.items.length, newItem)

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
        # detailedItemCard.on('longClick', 'select', ->
        #   e.item.subtitle = "Checking in..."
        #   toWatchMenu.item(e.sectionIndex, e.itemIndex, e.item)
        #   detailedItemCard.hide()
        #   checkWatched episode, -> checkHandler(e)
        # )
        detailedItemCard.show()
    )
  toWatchMenu.show()

  callback() if callback?

initSettings = ->
  Settings.init()
  Settings.config {
    url: CONFIG_BASE_URL
    autoSave: true
  }, (e) ->
    signInWindow.hide()
    refreshModels()

initSettings()

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
      e.item.subtitle = "Loading..."
      mainMenu.item(e.sectionIndex, e.itemIndex, e.item)
      displayToWatchMenu ->
        e.item.subtitle = undefined
        mainMenu.item(e.sectionIndex, e.itemIndex, e.item)
    when 'advanced'
      advancedMenu = new UI.Menu
        sections: [
          items: [{
            title: 'Reset localStorage'
            action: ->
              localStorage.clear()
              initSettings()
              console.log "Local storage cleared"
          }, {
            title: 'Refresh'
            action: -> refreshModels()
          }]
        ]
      advancedMenu.on 'select', (e) -> e.item.action()
      advancedMenu.show()

mainMenu.show()
refreshModels()
