UI = require('ui')
Settings = require('settings')
Appinfo = require('appinfo')
async = require('async')
myutil = require('myutil')

Emitter = require('emitter')

trakttv = require('trakttv')
misc = require('misc')
cards = require('cards')
lookAndFeel = require('lookAndFeel')

ICON_MENU_UNCHECKED = 'images/icon_menu_unchecked.png'
ICON_MENU_CHECKED = 'images/icon_menu_checked.png'
ICON_MENU_CALENDAR = 'images/icon_calendar.png'
ICON_MENU_EYE = 'images/icon_eye.png'
ICON_MENU_HOME = 'images/icon_home.png'

createDefaultMenu = (menuDef) ->
  options = misc.merge(lookAndFeel.menuDefaults, menuDef || {})
  options.sections ?= [
    {
      items: [{
        title: "Loading..."
      }]
    }
  ]
  new UI.Menu options


updateMenuSections = (menu, sections) ->
  menu.sections []
  menu.sections sections

appendItemToSection = (menu, sectionIndex, newItem) ->
  newItemPosition = (menu.section sectionIndex).items.length

  menu.item sectionIndex, newItemPosition, newItem

changeSubtitleGivenEvent = (text, e) =>
  e.subtitle = text
  e.menu.item e.sectionIndex, e.itemIndex, e

isNextEpisodeForItemAired = (item) ->
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

flashSubtitle = (message, e, originalSubtitle = "") ->
  changeSubtitleGivenEvent message, e

  window.setTimeout(
    => changeSubtitleGivenEvent originalSubtitle, e
    lookAndFeel.TIMEOUT_SUBTITLE_NOTIFICATION
  )

flashSubtitleError = (err, e, originalSubtitle = "") ->
  flashSubtitle "Failed (#{err.message})", e, originalSubtitle

class ReadyEmitter
  constructor: () ->
    @_emitter = new Emitter()
    @_ready = false

  register: (callback) =>
    return callback(null) if @_ready
    callbackWrapper = () =>
      @_emitter.off 'ready', callbackWrapper
      callback(null)
    @_emitter.on 'ready', callbackWrapper

  notify: () =>
    @_ready = true
    @_emitter.emit 'ready', {}

class Menu
  constructor: () ->
    @readyEmitter = new ReadyEmitter()
    @menu = null

  whenReady: (callback) -> @readyEmitter.register(callback)

  show: -> @menu.show()


class ToWatch extends Menu
  constructor: ->
    super
    @icons =
      checked: ICON_MENU_CHECKED
      unchecked: ICON_MENU_UNCHECKED
    @menu = createDefaultMenu()

    @initHandlers()

  isEpisodeListedInSection: (episodeNumber, section) ->
    episodeNumber in (item.data.episodeNumber for item in section.items)

  initHandlers: ->
    @menu.on 'longSelect', (e) =>
      element = e.item
      data = e.item.data

      if element.data.completed
        # We need to uncheck
        changeSubtitleGivenEvent "Unchecking...", e

        trakttv.uncheckEpisode data.showID, data.seasonNumber, data.episodeNumber,
          (err) =>
            return flashSubtitleError(err, e, data.originalSubtitle) if err

            element.data.completed = false
            element.icon = @icons.unchecked
            element.subtitle = "Unchecked!"
            @menu.item e.sectionIndex, e.itemIndex, element

            window.setTimeout(
              () => changeSubtitleGivenEvent data.originalSubtitle, e
              lookAndFeel.TIMEOUT_SUBTITLE_NOTIFICATION
            )
      else
        # We need to check
        changeSubtitleGivenEvent "Checking...", e

        trakttv.checkEpisode data.showID, data.seasonNumber, data.episodeNumber,
          (err) =>
            return flashSubtitleError(err, e, data.originalSubtitle) if err

            element.data.completed = true
            element.icon = @icons.checked

            changeSubtitleGivenEvent "Checked!", e

            window.setTimeout(
              () => changeSubtitleGivenEvent data.originalSubtitle, e
              lookAndFeel.TIMEOUT_SUBTITLE_NOTIFICATION
            )

            trakttv.fetchShowProgress data.showID,
              (err, show) =>
                return cards.flashError(err) if err

                if not isNextEpisodeForItemAired(show)
                  return

                nextEpisode = show.next_episode
                thisSection = @menu.section e.sectionIndex

                if @isEpisodeListedInSection nextEpisode.number, thisSection
                  return

                newItem = @_createItem(
                  data.showID
                  data.showTitle
                  nextEpisode.title
                  nextEpisode.season
                  nextEpisode.number
                  false
                )

                appendItemToSection(@menu, e.sectionIndex, newItem)


    @menu.on 'select', (e) =>
      element = e.item
      data = element.data
      originalSubtitle = element.subtitle

      changeSubtitleGivenEvent "Loading...", e

      trakttv.getEpisodeData data.showID, data.seasonNumber, data.episodeNumber,
        (err, episodeInfo) =>
          return flashSubtitleError(err, e, data.originalSubtitle) if err

          detailedItemCard = new cards.Default(
            title: data.showTitle
            subtitle: "Season #{data.seasonNumber} Ep. #{data.episodeNumber}"
            body: "Title: #{episodeInfo.title}\n\
                   Overview: #{episodeInfo.overview}"
          )
          detailedItemCard.show()
          changeSubtitleGivenEvent originalSubtitle, e


  _createItem: (showID, showTitle, episodeTitle, seasonNumber, episodeNumber, completed) ->
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
    }


  update: (shows) ->
    console.log "Updating toWatch"
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

    updateMenuSections @menu, sections

    @readyEmitter.notify()

class Upcoming extends Menu
  constructor: (@TimeFormatAccessor, @userDateFormat = "D MMMM YYYY") ->
    super
    @menu = createDefaultMenu()

    @initHandlers()

  getUserTimeFormat: () ->
    if @TimeFormatAccessor.get() == '24'
      'HH:mm'
    else
      'h:mm a'

  update: (@calendar = @calendar) ->
    return unless @calendar?
    console.log "Updating Upcoming"
    sections =
      {
        title: moment(date).format(@userDateFormat)
        items:
          {
            title: item.show.title
            subtitle: "S#{item.episode.season}E#{item.episode.number} | #{moment(item.airs_at).format(@getUserTimeFormat())}"
            data:
              showID: item.show.ids.trakt
              showTitle: item.show.title
              seasonNumber: item.episode.season
              episodeNumber: item.episode.number
              airs_at: item.airs_at

          } for item in items when moment(item.airs_at).isAfter(@fromDate)
      } for date, items of @calendar

    updateMenuSections @menu, sections
    @readyEmitter.notify()

  show: ->
    @update()
    @menu.show()

  initHandlers: ->
    @menu.on 'select', (e) =>
      element = e.item
      data = e.item.data
      originalSubtitle = element.subtitle

      changeSubtitleGivenEvent "Loading...", e

      trakttv.getEpisodeData data.showID, data.seasonNumber, data.episodeNumber,
        (err, episodeInfo) =>
          return flashSubtitleError(err, e, data.originalSubtitle) if err

          detailedItemCard = new cards.Default(
            title: data.showTitle
            subtitle: "Season #{data.seasonNumber} Ep. #{data.episodeNumber}"
            body: "Airs on #{moment(data.airs_at).format(@userDateFormat)}\n\
                   at #{moment(data.airs_at).format(@getUserTimeFormat())}\n\
                   Title: #{episodeInfo.title}\n\
                   Overview: #{episodeInfo.overview}"
          )

          detailedItemCard.show()
          changeSubtitleGivenEvent originalSubtitle, e

class MyShows extends Menu
  constructor: () ->
    super
    @menu = createDefaultMenu()
    @menu.on 'select', (e) =>
      element = e.item
      data = e.item.data

      changeSubtitleGivenEvent "Loading...", e

      show = i for i in @shows when i.show.ids.trakt == data.showID

      seasonsMenu = new Seasons data.showID, data.showTitle, show.seasons
      seasonsMenu.whenReady (err) =>
        seasonsMenu.show()
        changeSubtitleGivenEvent "", e

  update: (@shows) ->
    console.log "Updating MyShows"

    sections = [
      items:
        {
          title: item.show.title
          data:
            showID: item.show.ids.trakt
            showTitle: item.show.title
        } for item in @shows
    ]

    updateMenuSections @menu, sections
    @readyEmitter.notify()

class Episodes extends Menu
  constructor: (showTitle, episodes) ->
    super
    @menu = createDefaultMenu(
      sections: [{
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
    )
    @menu.on 'select', (e) ->
      data = e.item.data
      detailedItemCard = new cards.Default(
        title: showTitle
        subtitle: "Season #{data.seasonNumber} Ep. #{data.episodeNumber}"
        body: "Title: #{data.episodeTitle}\n\
               Overview: #{data.overview}"
      )

      detailedItemCard.show()

    @readyEmitter.notify()

class Seasons extends Menu
  constructor: (showID, showTitle, seasons) ->
    super
    @menu = createDefaultMenu(
      sections: [{
        items:
          {
            title: "Season #{season.number}"
            data:
              seasonNumber: season.number
          } for season in seasons
      }]
    )

    @menu.on 'select', (e) =>
      element = e.item
      data = e.item.data

      originalSubtitle = element.subtitle
      changeSubtitleGivenEvent "Loading...", e

      season = s for s in seasons when s.number == data.seasonNumber

      async.map(
        season.episodes,
        (ep, callback) =>
          trakttv.getEpisodeData showID, data.seasonNumber, ep.number, callback
        (err, episodes) =>
          return flashSubtitleError(err, e, data.originalSubtitle) if err

          episodesMenu = new Episodes showTitle, episodes
          episodesMenu.whenReady (err) =>
            episodesMenu.show()
            changeSubtitleGivenEvent originalSubtitle, e
      )
    @readyEmitter.notify()


class Main extends Menu
  constructor: (TimeFormatAccessor, fetchData) ->
    super
    @toWatchMenu = new ToWatch()
    @myShowsMenu = new MyShows()
    @upcomingMenu = new Upcoming TimeFormatAccessor
    @advancedMenu = new Advanced fetchData, TimeFormatAccessor

    @menu = createDefaultMenu(
      sections: [
        items: [{
          title: 'To watch'
          icon: ICON_MENU_EYE
          data:
            id: 'toWatch'
        }, {
          title: 'Upcoming'
          icon: ICON_MENU_CALENDAR
          data:
            id: 'upcoming'
        }, {
          title: 'My shows'
          icon: ICON_MENU_HOME
          data:
            id: 'myShows'
        }, {
          title: 'Advanced'
          data:
            id: 'advanced'
        }]
      ]
    )

    @menu.on 'select', (e) =>
      element = e.item
      id = e.item.data.id

      switch id
        when 'toWatch'
          changeSubtitleGivenEvent "Loading...", e
          @toWatchMenu.whenReady (err) =>
            return flashSubtitleError(err, e) if err?
            @toWatchMenu.show()
            changeSubtitleGivenEvent "", e

        when 'upcoming'
          changeSubtitleGivenEvent "Loading...", e
          @upcomingMenu.whenReady (err) =>
            return flashSubtitleError(err, e) if err?
            @upcomingMenu.show()
            changeSubtitleGivenEvent "", e

        when 'myShows'
          changeSubtitleGivenEvent "Loading", e
          @myShowsMenu.whenReady (err) =>
            return flashSubtitleError(err, e) if err?
            @myShowsMenu.show()
            changeSubtitleGivenEvent "", e

        when 'advanced'
          @advancedMenu.show()

    @readyEmitter.notify()

class Advanced extends Menu
  constructor: (@fetchData, @TimeFormatAccessor) ->
    super()
    @menu = createDefaultMenu
      sections: [
        {
          items: [
            {
              title: "Time Format"
              subtitle: "#{@TimeFormatAccessor.get()}h"
              data:
                id: 'timeFormat'
            }, {
              title: 'Refresh shows'
              data:
                id: 'refresh'
            }, {
              title: 'Restore watchapp'
              data:
                id: 'restore'
            }
          ]
        }, {
          title: "About"
          items: [{
            title: "Version"
            subtitle: "#{Appinfo.versionLabel}"
          }, {
            title: "Author"
            subtitle: "Alessio Bogon @youtux"
          }]
        }

      ]
    @initHandlers()
    @readyEmitter.notify()

  initHandlers: ->
    @menu.on 'select', (e) =>
      element = e.item
      data = e.item.data

      switch data?.id
        when 'refresh'
          changeSubtitleGivenEvent "Refreshing...", e
          @fetchData (err) =>
            return flashSubtitleError(err, e) if err
            flashSubtitle "Done!", e

        when 'restore'
          localStorage.clear()

          new cards.Notification(
            title: "One more step"
            body: "The watchapp has been restored.\n\
                   Please close and open it again."
            true    # noEscape
          ).show()

        when 'timeFormat'
          if @TimeFormatAccessor.get() == '24'
            @TimeFormatAccessor.set '12'
            changeSubtitleGivenEvent "12h", e
          else
            @TimeFormatAccessor.set '24'
            changeSubtitleGivenEvent "24h", e

module.exports =
  Main: Main
  ToWatch: ToWatch
  Upcoming: Upcoming
  MyShows: MyShows
  Advanced: Advanced
