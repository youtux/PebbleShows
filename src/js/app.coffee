config = require('config')

ajax = require('ajax')
UI = require('ui')
Settings = require('settings')
Timeline = require('timeline')
Appinfo = require('appinfo')

async = require('async')

trakttv = require('trakttv')
menus = require('menus')
cards = require('cards')

subscriptionsAlreadyUpdated = false

logInfo = ->
  accessToken = Settings.option 'accessToken'
  if accessToken?
    accessToken = "#{accessToken[0..5]}..."

  console.log "accessToken: #{accessToken}"
  console.log "Version: #{Appinfo.versionLabel}"
  Pebble.getTimelineToken?(
    (token) -> console.log "Timeline user token: #{token[0..5]}..."
    (errorString) -> console.log errorString
  )

initSettings = () ->
  # TODO: Check why when returning from settings all the calls are duplicated
  Settings.init()
  Settings.config {
    url: config.PEBBLE_CONFIG_URL
    autoSave: true
  }, (e) ->
    console.log "Returned from settings"
    signInWindow.hide()
    fetchData(->)

setupEvents = (toWatchMenu, myShowsMenu, upcomingMenu, signInWindow) ->
  trakttv.on 'authorizationRequired', (event) ->
    message = event.message
    signInWindow.show()

  trakttv.on 'update', 'shows', (event) ->
    shows = event.shows
    Settings.data shows: shows
    toWatchMenu.update(shows)
    myShowsMenu.update(shows)
    updateSubscriptions shows

  trakttv.on 'update', 'calendar', (event) ->
    calendar = event.calendar
    Settings.data calendar: calendar
    upcomingMenu.update(calendar)

fetchData = (callback) ->
  async.parallel(
    [
      (getCalendarCallback) ->
        trakttv.getCalendar(
          moment().subtract(1, 'day').format('YYYY-MM-DD'),
          7,
          getCalendarCallback
        )
      trakttv.fetchToWatchList
    ],
    (err, result) ->
      callback err, null
  )


updateSubscriptions = (shows) ->
  if subscriptionsAlreadyUpdated
    return

  watchingShowIDs = ("#{item.show.ids.trakt}" for item in shows)
  console.log "The user is watching the following shows:
  #{JSON.stringify watchingShowIDs}"

  Pebble.timelineSubscriptions?(
    (topicsSubscribed) ->
      # TODO: use async
      subscriptionsAlreadyUpdated = true

      console.log("Current timeline subscriptions #{JSON.stringify topicsSubscribed}");
      # Subscribe to new shows
      watchingShowIDs.forEach (showID) ->
        if showID in topicsSubscribed
          return
        console.log "Subscribing to #{showID}"
        Pebble.timelineSubscribe("#{showID}",
          () -> console.log "Subscribed to #{showID}",
          (errorString) ->
            console.log "Error while subscribing to #{showID}: #{errorString}"
          )

      # Unsubscribe from removed shows
      topicsSubscribed.forEach (topic) ->
        if topic in watchingShowIDs
          return
        console.log "Unsubscribing from #{topic}"
        Pebble.timelineUnsubscribe("#{topic}",
          () -> console.log "Unsubscribed from #{topic}",
          (errorString) ->
            console.log "Error while unsubscribing from #{topic}: #{errorString}"
          )
  )

getLaunchData = (launchCode, callback) ->
  console.log "getLaunchData url: #{config.BASE_SERVER_URL}/api/getLaunchData/#{launchCode}"
  ajax
    url: "#{config.BASE_SERVER_URL}/api/getLaunchData/#{launchCode}"
    type: 'json'
    (data, status, request) ->
      console.log("GOT DATA: #{JSON.stringify data}")
      callback null, data
    (err, status, request) ->
      console.log("GOT error: #{JSON.stringify err}")
      if status == null
        err = new Error("Connection not available.")
      else
        err = new Error("Communication error (#{status}).")
      callback err

dispatchTimelineAction = (launchCode) ->
  getLaunchData(launchCode, (err, data) =>
    return cards.flashError(err) if err

    action = data.action
    episodeID = data.episodeID

    if action == 'markAsSeen'
      statusCard = cards.Notification.fromMessage(
        "Please wait"          # text
        "Marking episode..."   # title
        true                   # noEscape
      )
      statusCard.show()

      trakttv.markEpisode(episodeID, true, null, (err, result) =>
        if err
          cards.Error.fromError(err).show()
          statusCard.hide()
          return

        cards.Notification.fromMessage(
          "Show marked as seen."  # text
          "Success!"              # title
        ).show()

        statusCard.hide()
      )

    else if action == 'checkIn'
      statusCard = cards.Notification.fromMessage(
        "Please wait"              # text
        "Checking-in episode..."   # title
        true                       # noEscape
      )
      statusCard.show()

      trakttv.checkInEpisode(episodeID, (err, result) ->
        if err
          if err.status == 409
            cards.Error.fromMessage(
              "You are already watching the episode."
              "Hmmm..."
            ).show()
          else
            cards.Error.fromError(err).show()
        else
          cards.Notification.fromMessage(
            'Enjoy the show!'
            'Success!'
          ).show()
        statusCard.hide()
      )
    )

checkLaunchReason = (normalAppLaunchCallback, timelineLaunchCallback)->
  Timeline.launch (e) ->
    if e.action
      console.log "Timeline launch! launchCode: #{launchCode}"
      launchCode = e.launchCode
      timelineLaunchCallback null, launchCode
    else
      normalAppLaunchCallback null

class TimeFormat
  @get: -> (Settings.data 'TimeFormat') or '12'
  @set: (format) ->
    if format != '12' and format != '24'
      console.log "setTimeFormat: invalid argument #{format}"
      return
    Settings.data TimeFormat: format

normalAppLaunch = () ->
  mainMenu = new menus.Main TimeFormat, fetchData
  toWatchMenu = mainMenu.toWatchMenu
  upcomingMenu = mainMenu.upcomingMenu
  myShowsMenu = mainMenu.myShowsMenu

  setupEvents toWatchMenu, myShowsMenu, upcomingMenu, signInWindow

  if shows = Settings.data 'shows'
    toWatchMenu.update shows
    myShowsMenu.update myShowsMenu

  if calendar = Settings.data 'calendar'
    upcomingMenu.update calendar

  mainMenu.show()

  fetchData (err) ->
    return cards.flashError(err) if err

signInWindow = new cards.Error(
  title: 'Configuration required'
  body: 'Open the Pebble App on your phone and configure Shows.'
  true # noEscape
)

logInfo()
initSettings()
checkLaunchReason(
  normalAppLaunch
  (err, launchCode) -> dispatchTimelineAction launchCode, ->
)
