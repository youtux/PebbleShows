UI = require('ui')
Settings = require('settings')
Wakeup = require('wakeup')
Appinfo = require('appinfo')

trakttv = require('trakttv')
menus = require('menus')
cards = require('cards')
timeline = require('timeline')

CONFIG_BASE_URL = 'http://traktv-forwarder.herokuapp.com/'


console.log "accessToken: #{Settings.option 'accessToken'}"
console.log "Version: #{Appinfo.versionLabel}"


signInWindow = new UI.Card(
    title: 'Sign-in required'
    body: 'Open the Pebble App and configure Pebble Shows.'
  )
signInWindow.on 'click', 'back', ->
  # No escape :)
  return

trakttv.on 'authorizationRequired', (reason) ->
  signInWindow.show()


initSettings = ->
  Settings.init()
  Settings.config {
    url: "#{CONFIG_BASE_URL}"
    autoSave: true
  }, (e) ->
    console.log "Returned from settings"
    signInWindow.hide()
    trakttv.fetchToWatchList()

initSettings()


toWatchMenu = new menus.ToWatch()
myShowsMenu = new menus.MyShows()
upcomingMenu = new menus.Upcoming(days: 14)
mainMenu = new menus.Main()

trakttv.on 'update', 'shows', (shows) ->
  console.log "new update fired"
  toWatchMenu.update(shows)
  myShowsMenu.update(shows)
  for item in shows
    showID = item.show.ids.trakt
    timeline.subscribe(showID)

# trakttv.fetchToWatchList()

mainMenu.show()

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
            text =
              if err?
                "Communication error. Try again later"
              else
                "Episode marked as seen!"
            notification = cards.notification text
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
            console.log("CheckIn #{episodeID}. err: #{JSON.stringify err}")
            text =
              if (err? and result != 409)
                "Communication error. Try again later"
              else if (err? and result == 409)
                "You are already watching the episode."
              else
                "Episode check'd in. Enjoy it!"
            notification = cards.notification text
            notification.show()
            statusCard.hide()
          )
    )




Wakeup.launch (e) ->
  console.log "Launch reason: #{JSON.stringify e}"
  if e.reason == 'timelineAction'
    launchCode = e.args
    dispatchTimelineAction(launchCode)

