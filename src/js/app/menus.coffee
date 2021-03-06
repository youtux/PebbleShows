ajax = require('ajax')
async = require('async')
log = require('loglevel')
moment = require('moment.timezone')

Appinfo = require('appinfo')
Emitter = require('emitter')
Settings = require('settings')
UI = require('ui')

cards = require('cards')
config = require('config')
lookAndFeel = require('lookAndFeel')
misc = require('misc')
Trakttv = require('trakttv')
AppSettings = require 'appsettings'

ICON_MENU_UNCHECKED = 'images/icon_menu_unchecked.png'
ICON_MENU_CHECKED = 'images/icon_menu_checked.png'
ICON_MENU_CALENDAR = 'images/icon_calendar.png'
ICON_MENU_EYE = 'images/icon_eye.png'
ICON_MENU_POPULAR = 'images/icon_popular.png'
ICON_MENU_HOME = 'images/icon_home.png'

updateMenuSections = (menu, sections) ->
  menu.prop sections: sections

appendItemToSection = (menu, sectionIndex, newItem) ->
  newItemPosition = (menu.section sectionIndex).items.length

  menu.item sectionIndex, newItemPosition, newItem

changeSubtitleGivenEvent = (text, e) =>
  e.item.subtitle = text
  e.menu.item e.sectionIndex, e.itemIndex, e.item

isNextEpisodeForItemAired = (item) ->
  if not item.next_episode?
    return false
  season = s for s in item.seasons when s.number == item.next_episode.season
  if not season?
    return false
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

flashSubtitle = (message, e, originalSubtitle) ->
  originalSubtitle ?=
    if e.item.data
      e.item.data.originalSubtitle
    else
      ""
  changeSubtitleGivenEvent message, e

  window.setTimeout(
    => changeSubtitleGivenEvent originalSubtitle, e
    lookAndFeel.TIMEOUT_SUBTITLE_NOTIFICATION
  )

flashSubtitleError = (err, e, originalSubtitle) ->
  flashSubtitle "Failed (#{err.message})", e, originalSubtitle

convertTimezone = (date, userTimezone, showTimezone) =>
  date = moment(date)
  isUserAmerican = userTimezone.indexOf("America") >= 0
  isShowAmerican = showTimezone.indexOf("America") >= 0

  if isUserAmerican and isShowAmerican
    date.tz("America/New_York")
  date


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
  constructor: (menuDef) ->
    @readyEmitter = new ReadyEmitter()
    options = misc.merge(lookAndFeel.menuDefaults, menuDef || {})
    options.sections ?= [
      {
        items: [{
          title: "Loading..."
        }]
      }
    ]
    @menu = new UI.Menu options

  whenReady: (callback) -> @readyEmitter.register(callback)

  show: -> @menu.show()


class ToWatch extends Menu
  constructor: ->
    super()
    @icons =
      checked: ICON_MENU_CHECKED
      unchecked: ICON_MENU_UNCHECKED

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

        Trakttv.uncheckEpisode data.showID, data.seasonNumber, data.episodeNumber,
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

        Trakttv.checkEpisode data.showID, data.seasonNumber, data.episodeNumber,
          (err) =>
            return flashSubtitleError(err, e, data.originalSubtitle) if err

            element.data.completed = true
            element.icon = @icons.checked

            changeSubtitleGivenEvent "Checked!", e

            window.setTimeout(
              () => changeSubtitleGivenEvent data.originalSubtitle, e
              lookAndFeel.TIMEOUT_SUBTITLE_NOTIFICATION
            )

            Trakttv.fetchShowProgress data.showID,
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

      Trakttv.getEpisodeData data.showID, data.seasonNumber, data.episodeNumber,
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
    log.info "Updating toWatch"
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
  constructor: (@userTimezone = "America/New_York", @userDateFormat = "D MMMM YYYY", @fromDate = null) ->
    super()
    if @fromDate == null
      @fromDate = moment()

    @initHandlers()

  getUserTimeFormat: () ->
    if AppSettings.timeFormat == '24'
      'HH:mm'
    else
      'h:mm a'

  update: (@myShowsCalendar = @myShowsCalendar, @userTimezone = @userTimezone) ->
    return unless @myShowsCalendar?
    log.info "Updating Upcoming"

    calendarItems = JSON.parse JSON.stringify @myShowsCalendar

    calendarItems.forEach (item) =>
      item.episode.first_aired = convertTimezone(
        moment(item.episode.first_aired),
        @userTimezone,
        item.show.airs.timezone
      )

    calendarItems = calendarItems.filter (item) =>
      moment(item.episode.first_aired).isAfter(@fromDate)

    calendarItemsGrouped = misc.groupBy calendarItems, (item) =>
      item.episode.first_aired.format(@userDateFormat)

    if misc.isEmpty calendarItemsGrouped
      sections = [items: [ title: "No upcoming shows" ]]
    else
      sections =
        {
          title: dateFormatted
          items:
            {
              title: item.show.title
              subtitle: "S#{item.episode.season}E#{item.episode.number} | #{item.episode.first_aired.format(@getUserTimeFormat())}"
              data:
                showID: item.show.ids.trakt
                showTitle: item.show.title
                seasonNumber: item.episode.season
                episodeNumber: item.episode.number
                airs_at: item.episode.first_aired

            } for item in items
        } for dateFormatted, items of calendarItemsGrouped

    updateMenuSections @menu, sections
    @readyEmitter.notify()

  show: ->
    @update()
    @menu.show()

  initHandlers: ->
    AppSettings.on 'timeFormat', (event) => @update()
    @menu.on 'select', (e) =>
      element = e.item
      data = e.item.data
      originalSubtitle = element.subtitle

      changeSubtitleGivenEvent "Loading...", e

      Trakttv.getEpisodeData data.showID, data.seasonNumber, data.episodeNumber,
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
    super()
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
    log.info "Updating MyShows"

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
    super(
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
    super(
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
          Trakttv.getEpisodeData showID, data.seasonNumber, ep.number, callback
        (err, episodes) =>
          return flashSubtitleError(err, e, data.originalSubtitle) if err

          episodesMenu = new Episodes showTitle, episodes
          episodesMenu.whenReady (err) =>
            episodesMenu.show()
            changeSubtitleGivenEvent originalSubtitle, e
      )
    @readyEmitter.notify()

class Popular extends Menu
  constructor: () ->
    super()
    @emitter = new Emitter()

    @menu.on 'select', (e) =>
      element = e.item
      data = element.data

      changeSubtitleGivenEvent "Loading...", e

      Trakttv.getShowData data.showID, (err, showData) =>
        return flashSubtitleError(err, e) if err

        changeSubtitleGivenEvent data.originalSubtitle, e

        # bannerURL = "#{config.BASE_SERVER_URL}/convert2png64?url=#{encodeURIComponent showData.images.fanart.thumb}"
        # log.info "Banner URL: #{bannerURL}"

        detailedItemCard = new cards.Default(
          title: showData.title
          subtitle: showData.year
          body: "Overview: #{showData.overview}"
          # banner: bannerURL
        )
        detailedItemCard.show()


    @menu.on 'longSelect', (e) =>
      # Add to the watchlist
      element = e.item
      data = element.data

      if data.inWatchList
        changeSubtitleGivenEvent "Removing from watchlist...", e
        Trakttv.removeShowFromWatchList data.showID, (err, response) =>
          return flashSubtitleError(err, e) if err

          flashSubtitle "Done!", e
          data.inWatchList = false

          @emitter.emit 'change', 'watchList', {}
      else
        changeSubtitleGivenEvent "Adding to watchlist...", e
        Trakttv.addShowToWatchList data.showID, (err, response) =>
          return flashSubtitleError(err, e) if err

          flashSubtitle "Added to watchlist!", e
          data.inWatchList = true

          @emitter.emit 'change', 'watchList', {}

  on: (args...) -> @emitter.on(args...)

  update: (@popularShows) ->
    log.info "Updating popularMenu"
    sections = [
      items:
        {
          title: show.title
          subtitle: show.year
          data:
            originalSubtitle: show.year
            showID: show.ids.trakt
            inWatchList: false
        } for show in @popularShows
    ]

    updateMenuSections @menu, sections
    @readyEmitter.notify()


class Main extends Menu
  constructor: (fetchData, @userTimezone) ->
    @toWatchMenu = new ToWatch()
    @upcomingMenu = new Upcoming @userTimezone
    @popularMenu = new Popular()
    @myShowsMenu = new MyShows()

    @popularMenu.on 'change', 'watchList', (event) => fetchData(=>)

    @advancedMenu = new Advanced fetchData

    super(
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
          title: 'Popular'
          icon: ICON_MENU_POPULAR
          data:
            id: 'popular'
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

        when 'popular'
          changeSubtitleGivenEvent "Loading...", e
          @upcomingMenu.whenReady (err) =>
            return flashSubtitleError(err, e) if err?
            @popularMenu.show()
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
  constructor: (@fetchData) ->
    super(
      sections: [
        {
          items: [
            {
              title: "Time Format"
              subtitle: "#{AppSettings.timeFormat}h"
              data:
                id: 'timeFormat'
            },
            {
              title: "Calendar Days"
              subtitle: "#{AppSettings.calendarDays}"
              data:
                id: 'calendarDays'
            },
            {
              title: "Report a problem"
              data:
                id: 'reportProblem'
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
    )
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
          if AppSettings.timeFormat == '24'
            AppSettings.timeFormat = '12'
            changeSubtitleGivenEvent "12h", e
          else
            AppSettings.timeFormat = '24'
            changeSubtitleGivenEvent "24h", e

        when 'calendarDays'
          new_ = AppSettings.calendarDays + 7
          if new_ > 28
            new_ = 0
          AppSettings.calendarDays = new_
          changeSubtitleGivenEvent "#{new_}", e

        when 'reportProblem'
          logs = Settings.data 'logs'
          accountToken = Pebble.getAccountToken()

          changeSubtitleGivenEvent "Collecting logs...", e

          ajax(
            url: "#{config.LOG_SERVER}/#{accountToken}/logs"
            method:'post'
            type: 'json'
            data: {logs:logs}
            (data, status, request) ->
              changeSubtitleGivenEvent "", e
              landingCard = new cards.Notification(
                style: 'small'
                body: "Please send an email to #{config.SUPPORT_EMAIL}
                       including the following ID:\n\
                       #{accountToken}\n\
                       (Just take a photo)"
              ).show()
            (err, status, request) ->
              changeSubtitleGivenEvent "", e
              if status == null
                err = new Error("Unable to connect to the server.")
              else
                err = new Error("Communication error (#{status}).")
                err.status = status
              landingCard = cards.Error.fromError(err).show()
            )

module.exports =
  Main: Main
  ToWatch: ToWatch
  Upcoming: Upcoming
  MyShows: MyShows
  Advanced: Advanced
