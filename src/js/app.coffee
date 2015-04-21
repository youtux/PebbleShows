UI = require('ui')
Settings = require('settings')

trakttv = require('trakttv')
menus = require('menus')

VERSION = "1.2"

CONFIG_BASE_URL = 'http://traktv-forwarder.herokuapp.com/'
ICON_MENU_UNCHECKED = 'images/icon_menu_unchecked.png'
ICON_MENU_CHECKED = 'images/icon_menu_checked.png'
ICON_MENU_CALENDAR = 'images/icon_calendar.png'
ICON_MENU_EYE = 'images/icon_eye.png'
ICON_MENU_HOME = 'images/icon_home.png'


console.log "accessToken: #{Settings.option 'accessToken'}"


signInWindow = undefined

trakttv.on 'authorizationRequired', (reason) ->
  unless signInWindow?
    signInWindow = new UI.Card(
      title: 'Sign-in required'
      body: 'Open the Pebble App and configure Pebble Shows.'
    )
    signInWindow.on 'click', 'back', ->
      # No escape :)
      return
  signInWindow.show()

console.log "Version: #{VERSION}"


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


toWatchMenu = new menus.ToWatch(
  icons:
    checked: ICON_MENU_CHECKED
    unchecked: ICON_MENU_UNCHECKED
)

myShowsMenu = new menus.MyShows()

upcomingMenu = new menus.Upcoming(days: 14)

trakttv.on 'update', 'shows', (shows) ->
  console.log "new update fired"
  toWatchMenu.update(shows)
  myShowsMenu.update(shows)

trakttv.fetchToWatchList()

mainMenu = new UI.Menu
  sections: [
    items: [{
      title: 'To watch'
      icon: ICON_MENU_EYE
      id: 'toWatch'
    }, {
      title: 'Upcoming'
      icon: ICON_MENU_CALENDAR
      id: 'upcoming'
    }, {
      title: 'My shows'
      icon: ICON_MENU_HOME
      id: 'myShows'
    }, {
      title: 'Advanced'
      id: 'advanced'
    }]
  ]

mainMenu.show()

mainMenu.on 'select', (e) ->
  switch e.item.id
    when 'toWatch', 'upcoming', 'myShows'
      switch e.item.id
        when 'toWatch'
          trakttv.fetchToWatchList()
          toWatchMenu.show()
        when 'upcoming'
          upcomingMenu.show()
        when 'myShows'
          myShowsMenu.show()

    when 'advanced'
      advancedMenu = new UI.Menu
        sections: [
          items: [
            {
              title: 'Refresh shows'
              action: -> trakttv.fetchToWatchList()
            }, {
              title: 'Reset local data'
              action: ->
                localStorage.clear()
                initSettings()
                displaySignInWindow()

                console.log "Local storage cleared"
            }, {
              title: "Version: #{VERSION}"
            }
          ]
        ]
      advancedMenu.on 'select', (e) -> e.item.action()
      advancedMenu.show()

require('birthday')
