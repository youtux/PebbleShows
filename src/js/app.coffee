UI = require('ui')
Settings = require('settings')
Wakeup = require('wakeup')
Appinfo = require('appinfo')

trakttv = require('trakttv')
menus = require('menus')
cards = require('cards')
timeline = require('timeline')

config = require('config')


CONFIG_URL = "#{config.BASE_SERVER_URL}/pebbleConfig"

ICON_CHECK = 'images/icon_check.png'


console.log "accessToken: #{Settings.option 'accessToken'}"
console.log "Version: #{Appinfo.versionLabel}"
Pebble.getTimelineToken?(
  (token) -> console.log "Timeline user token: #{token}"
  (errorString) -> console.log errorString
)
Pebble.timelineSubscriptions?(
  (topics) ->
    console.log("Current timeline subscriptions #{JSON.stringify topics}");
  (errorString) ->
    console.log('Error getting subscriptions: ' + errorString);
)

signInWindow = new UI.Card(
    title: 'Sign-in required'
    body: 'Open the Pebble App and configure Pebble Shows.'
  )
signInWindow.on 'click', 'back', ->
  # No escape :)
  return

trakttv.on 'authorizationRequired', (reason) ->
  signInWindow.show()

updateSubscriptions = (cb) ->
  trakttv.fetchToWatchList (err, shows) ->
    watchingShowIDs = ("#{item.show.ids.trakt}" for item in shows)
    console.log "The user is watching the following shows:
    #{JSON.stringify watchingShowIDs}"

    Pebble.timelineSubscriptions?(
      (topicsSubscribed) ->
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

initSettings = ->
  Settings.init()
  Settings.config {
    url: "#{CONFIG_URL}"
    autoSave: true
  }, (e) ->
    console.log "Returned from settings"
    signInWindow.hide()
    updateSubscriptions()

initSettings()


toWatchMenu = new menus.ToWatch()
myShowsMenu = new menus.MyShows()
upcomingMenu = new menus.Upcoming(days: 14)
advancedMenu = new menus.Advanced
  initSettings: initSettings

mainMenu = new menus.Main
  toWatchMenu: toWatchMenu
  myShowsMenu: myShowsMenu
  upcomingMenu: upcomingMenu
  advancedMenu: advancedMenu


trakttv.on 'update', 'shows', (shows) ->
  console.log "new update fired"
  toWatchMenu.update(shows)
  myShowsMenu.update(shows)

mainMenu.show()
updateSubscriptions()

require('birthday')


dispatchTimelineAction = (launchCode) ->
  timeline.getLaunchData(launchCode,
    (err, data) ->
      action = data.action
      episodeID = data.episodeID
      if action == 'markAsSeen'
        statusCard = cards.noEscape
          title: "Marking episode..."
          body: "Please wait"
        statusCard.show()

        trakttv.markEpisode(episodeID, true, null,
          (err, result) ->
            console.log("MarkAsSeen #{episodeID}. err: #{err}")
            notification =
              if err?
                new UI.Card
                  title: "Error"
                  body: "Communication Error. Try again later"
              else
                new UI.Card
                  # icon: ICON_CHECK
                  title: "Success!"
                  body: "Episode marked as seen."
            notification.show()
            statusCard.hide()
          )
      else if action == 'checkIn'
        statusCard = cards.noEscape
          title: "Checking-in episode..."
          body: "Please wait"
        statusCard.show()

        trakttv.checkInEpisode(episodeID,
          (err, result) ->
            console.log("CheckIn #{episodeID}. err: #{JSON.stringify err}, result: #{JSON.stringify result}")
            notification =
              if (err? and result != 409)
                new UI.Card
                  title: "Error"
                  body: "Communication error. Try again later"
              else if (err? and result == 409)
                console.log "Creating already watching card"
                new UI.Card
                  title: "Hmmm..."
                  body: "You are already watching the episode."
              else
                new UI.Card
                  # icon: ICON_CHECK
                  title: "Success!"
                  body: "Episode check'd in. Enjoy it!"
            notification.show()
            statusCard.hide()
          )
    )




Wakeup.launch (e) ->
  console.log "Launch reason: #{JSON.stringify e}"
  if e.reason == 'timelineAction'
    launchCode = e.args
    dispatchTimelineAction(launchCode)

