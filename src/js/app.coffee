ajax = require('ajax')
async = require('async')
log = require('loglevel')
moment = require('moment')

Appinfo = require('appinfo')
Settings = require('settings')
Timeline = require('timeline')
UI = require('ui')

config = require('config')
Trakttv = require('trakttv')
menus = require('menus')
misc = require('misc')
MyTimeline = require('mytimeline')
cards = require('cards')
AppSettings = require('appsettings')

setupLogging = () ->
  @sessionLogs ?= []
  @originalFactory ?= log.methodFactory
  log.methodFactory = (methodName, logLevel) =>
    return (message) =>
      @originalFactory(methodName, logLevel)(message)

      logMessage = "[#{new Date().toISOString()}] #{methodName}: #{message}"
      sessionLogs.push(logMessage)

      Settings.data 'logs': sessionLogs
  log.enableAll()

logInfo = ->
  accessToken = Settings.option 'accessToken'
  if accessToken?
    accessToken = "#{accessToken[0..5]}..."

  log.info "accessToken: #{accessToken}"
  log.info "Version: #{Appinfo.versionLabel}"
  Pebble.getTimelineToken?(
    (token) -> log.info "Timeline user token: #{token}..."
    (errorString) -> log.error errorString
  )

initSettings = () ->
  Settings.config {
    url: config.PEBBLE_CONFIG_URL
    autoSave: true
  }, (e) ->
    log.info "Returned from settings"
    signInWindow.hide()
    fetchData(->)

showIDToTopic = (showID, pacificTimezoneCorrection) =>
  if pacificTimezoneCorrection
    "schedule-pacific-#{showID}"
  else
    "schedule-#{showID}"

# TODO: move this logic somewhere else
requiresPacificTimezoneCorrection = (timezone) =>
  timezone == "America/Los_Angeles"

subscribeToShows = (showIDList, userTimezone) =>
  topics = (
    showIDToTopic(
      showID,
      requiresPacificTimezoneCorrection(userTimezone)
    ) for showID in showIDList
  )
  MyTimeline.updateSubscriptions topics

subscribeToShowsWhenDataAvailable = (@showIDList=@showIDList, @userTimezone=@userTimezone) ->
  if @showIDList and @userTimezone
    subscribeToShows(@showIDList, @userTimezone)

setupEvents = (toWatchMenu, upcomingMenu, popularMenu, myShowsMenu, signInWindow) ->
  Trakttv.on 'authorizationRequired', (event) ->
    message = event.message
    signInWindow.show()

  Trakttv.on 'update', 'shows', (event) ->
    shows = event.shows
    Settings.data shows: shows
    toWatchMenu.update(shows)
    myShowsMenu.update(shows)

    watchingShowIDs = ("#{item.show.ids.trakt}" for item in shows)
    log.info "The user is watching the following shows:
            #{JSON.stringify watchingShowIDs}"
    # MyTimeline.updateSubscriptions watchingShowIDs
    subscribeToShowsWhenDataAvailable(watchingShowIDs, null)

  Trakttv.on 'update', 'popularShows', (event) ->
    popularShows = event.popularShows
    Settings.data popularShows: popularShows
    popularMenu.update popularShows

  Trakttv.on 'update', 'myShowsCalendar', (event) ->
    myShowsCalendar = event.myShowsCalendar
    Settings.data myShowsCalendar: myShowsCalendar
    upcomingMenu.update(myShowsCalendar)

  Trakttv.on 'update', 'userSettings', (event) ->
    userSettings = event.userSettings
    Settings.data userSettings: userSettings
    subscribeToShowsWhenDataAvailable(null, userSettings.account.timezone)
    upcomingMenu.update(null, userSettings.account.timezone)

  AppSettings.on 'calendarDays', (event) ->
    fetchMyShowsCalendar (err) ->
      log.error("fetchMyShowsCalendar error: #{err.message}") if err
      return

fetchMyShowsCalendar = (cb) ->
  Trakttv.getMyShowsCalendar(
    moment().subtract(1, 'day').format('YYYY-MM-DD'),
    AppSettings.calendarDays + 1,
    cb
  )

fetchData = (callback) ->
  async.parallel(
    [
      Trakttv.fetchToWatchList
      fetchMyShowsCalendar
      (cb) => Trakttv.getPopular(null, cb)
      (cb) => Trakttv.getUserSettings (err, userSettings) =>
        return cb(err) if err
        Settings.data userSettings: userSettings
        cb(err, userSettings)
    ]
    (err, result) =>
      log.error("fetchData error: #{err}, #{err.message}") if err
      callback err, null
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
        err = new Error("Unable to connect to the server.")
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

      Trakttv.markEpisode(episodeID, true, null, (err, result) =>
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

      Trakttv.checkInEpisode(episodeID, (err, result) ->
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



normalAppLaunch = () ->
  userTimezone = (Settings.data 'userSettings')?.account.timezone
  mainMenu = new menus.Main fetchData, userTimezone
  toWatchMenu = mainMenu.toWatchMenu
  upcomingMenu = mainMenu.upcomingMenu
  popularMenu = mainMenu.popularMenu
  myShowsMenu = mainMenu.myShowsMenu

  setupEvents toWatchMenu, upcomingMenu, popularMenu, myShowsMenu, signInWindow

  if shows = Settings.data 'shows'
    toWatchMenu.update shows
    myShowsMenu.update myShowsMenu

  if myShowsCalendar = Settings.data 'myShowsCalendar'
    upcomingMenu.update myShowsCalendar

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
