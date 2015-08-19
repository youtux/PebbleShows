UI = require('ui')
Settings = require('settings')
Appinfo = require('appinfo')
async = require('async')
myutil = require('myutil')

trakttv = require('trakttv')

menus = {}

ICON_MENU_UNCHECKED = 'images/icon_menu_unchecked.png'
ICON_MENU_CHECKED = 'images/icon_menu_checked.png'
ICON_MENU_CALENDAR = 'images/icon_calendar.png'
ICON_MENU_EYE = 'images/icon_eye.png'
ICON_MENU_HOME = 'images/icon_home.png'

colorsAvailable = Pebble.getActiveWatchInfo?().platform == "basalt"

defaults =
  if colorsAvailable
    backgroundColor: 'oxfordBlue'
    textColor: 'white'
    thirdColor: 'orange'
  else
    backgroundColor: 'white'
    textColor: 'black'
    thirdColor: 'black'

menuDefaults =
  if colorsAvailable
    backgroundColor: defaults.backgroundColor
    textColor: defaults.textColor
    highlightBackgroundColor: defaults.thirdColor #
    highlightTextColor: 'white'
    fullscreen: true
  else
    backgroundColor: defaults.backgroundColor
    textColor: defaults.textColor
    highlightBackgroundColor: defaults.backgroundColor
    highlightTextColor: defaults.textColor
    fullscreen: false

cardDefaults =
  if colorsAvailable
    backgroundColor: defaults.backgroundColor
    textColor: defaults.textColor
    titleColor: defaults.thirdColor
    subtitleColor: defaults.thirdColor
    bodyColor: defaults.textColor
    fullscreen: true
    style: 'small'
    scrollable: true
  else
    backgroundColor: defaults.backgroundColor
    textColor: defaults.textColor
    titleColor: defaults.textColor
    subtitleColor: defaults.textColor
    bodyColor: defaults.textColor
    fullscreen: false
    style: 'small'
    scrollable: true


createDefaultMenu = (menuDef) ->
  options = myutil.shadow(menuDefaults, menuDef || {})
  options.sections ?= [
    {
      items: [{
        title: "Loading..."
      }]
    }
  ]
  new UI.Menu options

createDefaultCard = (cardDef) ->
  options = myutil.shadow(cardDefaults, cardDef || {})
  new UI.Card options

isNextEpisodeForItemAired = (item) ->
  # console.log "isNextEpisodeForItemAired of item: #{JSON.stringify item.show.title}"
  # console.log "item.next_episode #{JSON.stringify item.next_episode}"
  return false unless item.next_episode?
  if item.next_episode.season > item.seasons.length
    return false
  season = s for s in item.seasons when s.number == item.next_episode.season
  if item.next_episode.number > season.aired
    return false
  true

compareByKey = (key) ->
  (a, b) ->
    -1 if a[key] < b[key]
    0 if a[key] == b[key]
    1 if a[key] > b[key]

compareByFunction = (keyFunction) ->
  (a, b) ->
    -1 if keyFunction(a) < keyFunction(b)
    0 if keyFunction(a) == keyFunction(b)
    1 if keyFunction(a) > keyFunction(b)

class ToWatch
  constructor: ->
    @icons =
      checked: ICON_MENU_CHECKED
      unchecked: ICON_MENU_UNCHECKED
    @menu = createDefaultMenu()

    @initHandlers()

  show: -> @menu.show()

  initHandlers: ->
    @menu.on 'longSelect', (e) =>
      console.log "element before the change: #{JSON.stringify e.item}"
      element = e.item
      data = e.item.data

      displaySubtitle = (text) =>
        element.subtitle = text
        @menu.item e.sectionIndex, e.itemIndex, element

      if element.data.completed
        # We need to uncheck
        displaySubtitle "Unchecking..."

        trakttv.uncheckEpisode data.showID, data.seasonNumber, data.episodeNumber,
          (err) =>
            if err?
              # Rollback
              displaySubtitle "Failed"

              window.setTimeout(
                () => displaySubtitle data.originalSubtitle
                2000
              )
              return
            element.data.completed = false
            element.icon = @icons.unchecked
            element.subtitle = "Unchecked!"
            @menu.item e.sectionIndex, e.itemIndex, element

            window.setTimeout(
              () => displaySubtitle data.originalSubtitle
              2000
            )
      else
        # We need to check
        displaySubtitle "Checking..."

        trakttv.checkEpisode data.showID, data.seasonNumber, data.episodeNumber,
          (err) =>
            if err?
              # Rollback
              displaySubtitle "Failed"

              window.setTimeout(
                () => displaySubtitle data.originalSubtitle
                2000
              )
              return
            element.data.completed = true
            element.icon = @icons.checked
            element.subtitle = "Checked!"
            @menu.item e.sectionIndex, e.itemIndex, element

            window.setTimeout(
              () => displaySubtitle data.originalSubtitle
              2000
            )

            if data.isNextEpisodeListed
              return
            trakttv.fetchShowProgress data.showID,
              (err, show) =>
                # TODO: if err, reset the checked flag and subtitles
                return if err?
                console.log "RELOADED ShowID: #{data.showID}"
                if not isNextEpisodeForItemAired(show)
                  return
                data.isNextEpisodeListed = true

                newItem = @_createItem(
                  data.showID
                  data.shotTItle
                  show.next_episode.title
                  show.next_episode.season
                  show.next_episode.number
                  false
                  false
                )
                console.log "toWatchMenu.item(#{e.sectionIndex}, #{e.section.items.length}, #{JSON.stringify newItem}"

                # TODO: use a function to add items
                @menu.item e.sectionIndex, e.section.items.length, newItem


    @menu.on 'select', (e) =>
      element = e.item
      data = element.data
      trakttv.getEpisodeData data.showID, data.seasonNumber, data.episodeNumber,
        (err, episodeInfo) =>
          detailedItemCard = createDefaultCard
            title: data.showTitle
            subtitle: "Season #{data.seasonNumber} Ep. #{data.episodeNumber}"
            body: "Title: #{episodeInfo.title}\n\
                   Overview: #{episodeInfo.overview}"

          detailedItemCard.show()

    console.log "toWatchmenu created"

  _createItem: (showID, showTitle, episodeTitle, seasonNumber, episodeNumber, isNextEpisodeListed, completed) ->
    subtitle = "Season #{seasonNumber} Ep. #{episodeNumber}"
    return {
      title: episodeTitle
      subtitle: subtitle
      icon: if completed then @icons.checked else @icons.unchecked
      data:
        showID: showID
        showTitle: showTitle
        originalSubtitle: subtitle
        episodeNumber: episodeNumber
        seasonNumber: seasonNumber
        completed: completed
        isNextEpisodeListed: isNextEpisodeListed # TODO: delete me
    }


  update: (shows) ->
    sections =
      {
        title: item.show.title
        items: [
          @_createItem(
            item.show.ids.trakt
            item.show.title
            item.next_episode.title
            item.next_episode.season
            item.next_episode.number
            false
            false                     # completed
          )
        ]
      } for item in shows when isNextEpisodeForItemAired(item)

    # TODO: use a better method to clear sections (sections > 1 might remain)
    if sections.length == 0
      sections = [
        items: [
          title: "No shows to watch"
        ]
      ]
    console.log "Updating toWatch"
    @menu.section(idx, s) for s, idx in sections

menus.ToWatch = ToWatch

# TODO: Fetch user preferences, and show correct date/hour
class Upcoming
  constructor: (@userDateFormat = "D MMMM YYYY") ->
    @menu = createDefaultMenu()

    @initHandlers()
    # @reload()

  update: (calendar) ->
    # console.log "Updating UpcomingMenu: #{JSON.stringify calendar}"
    sections =
      {
        title: moment(date).format(@userDateFormat)
        items:
          {
            title: item.show.title
            subtitle: "S#{item.episode.season}E#{item.episode.number} | #{moment(item.airs_at).format('HH:mm')}"
            data:
              showID: item.show.ids.trakt
              showTitle: item.show.title
              seasonNumber: item.episode.season
              episodeNumber: item.episode.number
              airs_at: item.airs_at

          } for item in items when moment(item.airs_at).isAfter(@fromDate)
      } for date, items of calendar

    # console.log "---- #{JSON.stringify sections}"

    @menu.section(idx, s) for s, idx in sections
    # sections.forEach (s, idx) => @menu.section(idx, s)

  show: ->
    @menu.show()

  initHandlers: ->
    @menu.on 'select', (e) =>
      data = e.item.data

      trakttv.getEpisodeData data.showID, data.seasonNumber, data.episodeNumber,
        (err, episodeInfo) =>
          #TODO: handle error
          detailedItemCard = createDefaultCard
            title: data.showTitle
            subtitle: "Season #{data.seasonNumber} Ep. #{data.episodeNumber}"
            body: "Airs on #{moment(data.airs_at).format(@userDateFormat)}\n\
                   at #{moment(data.airs_at).format('HH:mm')}\n\
                   Title: #{episodeInfo.title}\n\
                   Overview: #{episodeInfo.overview}"

          detailedItemCard.show()

menus.Upcoming = Upcoming

class MyShows
  constructor: () ->
    @menu = createDefaultMenu()

    @initHandlers()

  show: -> @menu.show()

  initHandlers: ->
    @menu.on 'select', (e) =>
      data = e.item.data
      showTitle = e.item.data.showTitle

      item = i for i in @show_list when i.show.ids.trakt == data.showID
      seasonsMenu = createDefaultMenu
        sections: [{
          items:
            {
              title: "Season #{season.number}"
              data:
                showID: data.showID
                seasonNumber: season.number
            } for season in item.seasons
        }]

      seasonsMenu.show()

      seasonsMenu.on 'select', (e) ->
        data = e.item.data
        season = s for s in item.seasons when s.number == data.seasonNumber
        episodesMenu = createDefaultMenu()
        episodesMenu.show()

        async.map(
          season.episodes,
          (ep, cb) ->
            trakttv.getEpisodeData data.showID, data.seasonNumber, ep.number,
              (err, episode) ->
                # TODO: maybe we can print something else?
                if err?
                  episode = {}
                cb(null, episode)
          (err, episodes) ->
            episodesMenuSections = [{
              items:
                {
                  title: episode.title
                  subtitle: "Season #{episode.season} Ep. #{episode.number}"
                  data:
                    episodeTitle: episode.title
                    overview: episode.overview
                    seasonNumber: episode.season
                    episodeNumber: episode.number
                } for episode in episodes
            }]
            episodesMenu.section(idx, s) for s, idx in episodesMenuSections

            episodesMenu.on 'select', (e) ->
              data = e.item.data
              # TODO: colorize this card
              detailedItemCard = createDefaultCard
                title: showTitle
                subtitle: "Season #{data.seasonNumber} Ep. #{data.episodeNumber}"
                body: "Title: #{data.episodeTitle}\n\
                       Overview: #{data.overview}"

              detailedItemCard.show()
          )
  update: (shows) ->
    sortedShows = shows[..]
    sortedShows.sort compareByFunction (e) -> moment(e.last_watched_at)

    @show_list = sortedShows

    sections = [
      items:
        {
          title: item.show.title
          data:
            showID: item.show.ids.trakt
            showTitle: item.show.title
        } for item in @show_list
    ]

    @menu.section(idx, s) for s, idx in sections
    console.log "showsMenu updated"

menus.MyShows = MyShows

class Main
  constructor: (opts)->
    @toWatchMenu = opts.toWatchMenu
    @upcomingMenu = opts.upcomingMenu
    @myShowsMenu = opts.myShowsMenu
    @advancedMenu = opts.advancedMenu
    @menu = createDefaultMenu
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
    @initHandlers()

  initHandlers: ->
    @menu.on 'select', (e) =>
      switch e.item.id
        when 'toWatch', 'upcoming', 'myShows'
          switch e.item.id
            when 'toWatch'
              # trakttv.fetchToWatchList()
              @toWatchMenu.show()
            when 'upcoming'
              @upcomingMenu.show()
            when 'myShows'
              @myShowsMenu.show()

        when 'advanced'
          @advancedMenu.show()

  show: ->
    @menu.show()

menus.Main = Main

class Advanced
  constructor: (opts) ->
    @initSettings = opts.initSettings
    @menu = createDefaultMenu
      sections: [
        items: [
          # TODO: an option to reset the menus
          {
            title: 'Reset local data'
            action: =>
              localStorage.clear()
              @initSettings()

              console.log "Local storage cleared"
          }, {
            title: "Version: #{Appinfo.versionLabel}"
            action: ->
          }
        ]
      ]
    @initHandlers()

  initHandlers: ->
    @menu.on 'select', (e) -> e.item.action()

  show: ->
    @menu.show()

menus.Advanced = Advanced

module.exports = menus
