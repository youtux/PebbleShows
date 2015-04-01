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

userDateFormat = "D MMMM YYYY"

Settings.option 'accessToken', '3e391f60e4914df9177042c0bdcec849ef2f039896d28c13c7adef61720eb50a'

console.log "accessToken: #{Settings.option 'accessToken'}"


signInWindow = undefined
shows = Settings.data 'shows'

trakttv.on 'authorizationRequired', (reason) ->
  signInWindow = new UI.Card(
    title: 'Sign-in required'
    body: 'Open the Pebble App and configure Pebble Shows.'
  )
  signInWindow.on 'click', 'back', ->
    # No escape :)
    return
  signInWindow.show()




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


displayUpcomingMenu = (callback) ->
  startingDate = moment().format('YYYY-MM-DD')
  days = 7
  trakttv.request "/calendars/shows/#{startingDate}/#{days}",
    (response, status, req)->
      sections =
        {
          title: moment(date).format(userDateFormat)
          items:
            {
              title: item.show.title
              subtitle: "S#{item.episode.season}E#{item.episode.number} | #{moment(item.airs_at).format('HH:MM')}"
              data:
                showID: item.show.ids.trakt
                seasonNumber: item.episode.season
                episodeNumber: item.episode.number

            } for item in items when moment(item.airs_at) >= moment()
        } for date, items of response
      # console.log "sections: #{JSON.stringify sections}"

      upcomingMenu = new UI.Menu(
        sections: sections
      )

      upcomingMenu.show()

      upcomingMenu.on 'select', (e) ->
        element = e.item
        data = element.data
        getOrFetchEpisodeData data.showID, data.seasonNumber, data.episodeNumber, (episode) ->
          # console.log "response for #{data.showID}, #{data.seasonNumber}, #{data.episodeNumber}"
          # console.log "--> #{JSON.stringify episode}"
          detailedItemCard = new UI.Card(
            title: episode.showTitle
            subtitle: "Season #{episode.seasonNumber} Ep. #{episode.episodeNumber}"
            body: "Title: #{episode.episodeTitle}\n\
                   Overview: #{episode.overview}"
            style: 'small'
            scrollable: true
          )
          detailedItemCard.show()
      callback() if callback?




console.log "Version: #{VERSION}"


initSettings = ->
  Settings.init()
  Settings.config {
    url: "#{CONFIG_BASE_URL}"
    autoSave: true
  }, (e) ->
    console.log "Returned from settings"
    signInWindow.hide()
    trakttv.refreshModels()

initSettings()


toWatchMenu = new menus.ToWatchMenu(
  icons:
    checked: ICON_MENU_CHECKED
    unchecked: ICON_MENU_UNCHECKED
)

showsMenu = menus.shows.createShowsMenu()

trakttv.on 'update', 'shows', (shows) ->
  console.log "new update fired"
  toWatchMenu.update(shows)
  menus.shows.updateShowsMenu(showsMenu, shows)

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
          trakttv.refreshModels()
          toWatchMenu.menu.show()
        when 'upcoming' then displayUpcomingMenu
        when 'myShows'
          trakttv.refreshModels()
          showsMenu.show()

      # displayFunction ->
      #   delete e.item.subtitle
      #   mainMenu.item(e.sectionIndex, e.itemIndex, e.item)

    when 'advanced'
      advancedMenu = new UI.Menu
        sections: [
          items: [
            {
              title: 'Refresh shows'
              action: -> trakttv.refreshModels()
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

trakttv.refreshModels()

# TODO: try a trakttv request, if fails display sign in window
