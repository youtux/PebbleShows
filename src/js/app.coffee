config = require('config')

ajax = require('ajax')
UI = require('ui')
Settings = require('settings')
Timeline = require('timeline')
Appinfo = require('appinfo')

async = require('async')
log = require('loglevel')

trakttv = require('trakttv')
menus = require('menus')
cards = require('cards')

subscriptionsAlreadyUpdated = false

setupLogging = () ->
  @originalFactory ?= log.methodFactory
  log.methodFactory = (methodName, logLevel) =>
    return (message) =>
      @originalFactory(methodName, logLevel)(message)

      logMessage = "[#{new Date().toISOString()}] #{methodName}: #{message}"
      logs = (Settings.data 'logs') or []
      logs.push(logMessage)
      Settings.data 'logs': logs
  log.enableAll()

logInfo = ->
  accessToken = Settings.option 'accessToken'
  if accessToken?
    accessToken = "#{accessToken[0..5]}..."

  log.info "accessToken: #{accessToken}"
  log.info "Version: #{Appinfo.versionLabel}"
  Pebble.getTimelineToken?(
    (token) -> log.info "Timeline user token: #{token[0..5]}..."
    (errorString) -> log.error errorString
  )

initSettings = () ->
  # TODO: Check why when returning from settings all the calls are duplicated
  Settings.init()
  Settings.config {
    url: config.PEBBLE_CONFIG_URL
    autoSave: true
  }, (e) ->
    log.info "Returned from settings"
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
  log.info "The user is watching the following shows:
  #{JSON.stringify watchingShowIDs}"

  Pebble.timelineSubscriptions?(
    (topicsSubscribed) ->
      # TODO: use async
      subscriptionsAlreadyUpdated = true

      log.info("Current timeline subscriptions #{JSON.stringify topicsSubscribed}");
      # Subscribe to new shows
      watchingShowIDs.forEach (showID) ->
        if showID in topicsSubscribed
          return
        log.info "Subscribing to #{showID}"
        Pebble.timelineSubscribe("#{showID}",
          () -> log.info "Subscribed to #{showID}",
          (errorString) ->
            log.error "Error while subscribing to #{showID}: #{errorString}"
          )

      # Unsubscribe from removed shows
      topicsSubscribed.forEach (topic) ->
        if topic in watchingShowIDs
          return
        log.info "Unsubscribing from #{topic}"
        Pebble.timelineUnsubscribe("#{topic}",
          () -> log.info "Unsubscribed from #{topic}",
          (errorString) ->
            log.error "Error while unsubscribing from #{topic}: #{errorString}"
          )
  )

getLaunchData = (launchCode, callback) ->
  log.info "getLaunchData url: #{config.BASE_SERVER_URL}/api/getLaunchData/#{launchCode}"
  ajax
    url: "#{config.BASE_SERVER_URL}/api/getLaunchData/#{launchCode}"
    type: 'json'
    (data, status, request) ->
      log.info("GOT DATA: #{JSON.stringify data}")
      callback null, data
    (err, status, request) ->
      log.error("GOT error: #{JSON.stringify err}")
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
      log.info "Timeline launch! launchCode: #{launchCode}"
      launchCode = e.launchCode
      timelineLaunchCallback null, launchCode
    else
      normalAppLaunchCallback null

class TimeFormat
  @get: -> (Settings.data 'TimeFormat') or '12'
  @set: (format) ->
    if format != '12' and format != '24'
      log.warn "setTimeFormat: invalid argument #{format}"
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

setupLogging()
logInfo()
initSettings()
checkLaunchReason(
  normalAppLaunch
  (err, launchCode) -> dispatchTimelineAction launchCode, ->
)
