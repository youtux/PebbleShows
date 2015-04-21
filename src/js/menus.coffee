UI = require('ui')
trakttv = require('trakttv')
async = require('async')
Settings = require('settings')

menus = {}

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
  constructor: (opt) ->
    @icons = opt.icons
    @menu = new UI.Menu(
      sections:[
        {
          items: [{
            title: "Loading shows..."
            }]
        }
      ]
    )

    @initHandlers()

  show: -> @menu.show()

  initHandlers: ->
    @menu.on 'longSelect', (e) =>
      console.log "element before the change: #{JSON.stringify e.item}"
      element = e.item
      data = e.item.data
      data.previousSubtitle = element.subtitle

      element.subtitle =
        if element.data.completed
          "Unchecking..."
        else
          "Checking..."

      markAsCompleted = not element.data.completed

      @menu.item(e.sectionIndex, e.itemIndex, element)

      trakttv.modifyCheckState
        showID: data.showID
        episodeNumber: data.episodeNumber
        seasonNumber: data.seasonNumber
        completed: markAsCompleted
        () =>
          isNowCompleted = not data.completed
          console.log "episode is now #{JSON.stringify e.item}"

          if isNowCompleted
            element.data.completed = true
            element.icon = @icons.checked
          else
            element.data.completed = false
            element.icon = @icons.unchecked

          element.subtitle = element.data.previousSubtitle
          delete element.data.previousSubtitle

          @menu.item(e.sectionIndex, e.itemIndex, element)

          if isNowCompleted and not element.isNextEpisodeListed
            # TODO: clean this mess using getEpisodeData
            trakttv.fetchShowProgress data.showID, (reloadedShow) =>
              console.log "RELOADED ShowID: #{reloadedShow.show.ids.trakt}, title: #{reloadedShow.show.title}"
              # console.log "item: #{JSON.stringify reloadedShow}"
              if isNextEpisodeForItemAired(reloadedShow) and not element.isNextEpisodeListed
                element.isNextEpisodeListed = true

                newItem = @_createItem(
                  showID: data.showID
                  episodeTitle: reloadedShow.next_episode.title
                  seasonNumber: reloadedShow.next_episode.season
                  episodeNumber: reloadedShow.next_episode.number
                  completed: false
                )
                console.log "toWatchMenu.item(#{e.sectionIndex}, #{e.section.items.length}, #{JSON.stringify newItem}"

                # TODO: use a function to add items
                @menu.item(e.sectionIndex, e.section.items.length, newItem)
        () ->
          element.subtitle = element.data.previousSubtitle
          delete element.data.previousSubtitle

          @menu.item(e.sectionIndex, e.itemIndex, element)

    @menu.on 'select', (e) ->
      element = e.item
      data = element.data
      trakttv.getOrFetchEpisodeData data.showID, data.seasonNumber, data.episodeNumber, (episode) ->
        detailedItemCard = new UI.Card(
          title: episode.showTitle
          subtitle: "Season #{episode.seasonNumber} Ep. #{episode.episodeNumber}"
          body: "Title: #{episode.episodeTitle}\n\
                 Overview: #{episode.overview}"
          style: 'small'
          scrollable: true
        )
        detailedItemCard.show()

    console.log "toWatchmenu created"

  _createItem: (opt) ->
    for key in ['showID', 'episodeTitle', 'seasonNumber', 'episodeNumber', 'completed']
      unless opt[key]?
        console.log "ERROR: #{key} not in #{JSON.stringify opt}"
        return
    # console.log "opt.completed: #{opt.completed}"
    # console.log "icon chosed: " + JSON.stringify @icons
    {
      title: opt.episodeTitle
      subtitle: "Season #{opt.seasonNumber} Ep. #{opt.episodeNumber}"
      icon: if opt.completed then @icons.checked else @icons.unchecked
      data:
        showID: opt.showID
        episodeNumber: opt.episodeNumber
        seasonNumber: opt.seasonNumber
        completed: opt.completed
        isNextEpisodeListed: opt.isNextEpisodeListed # TODO: delete me
    }

  update: (shows) ->
    sections =
      {
        title: item.show.title
        items: [
          @_createItem(
            showID: item.show.ids.trakt
            episodeTitle: item.next_episode.title
            seasonNumber: item.next_episode.season
            episodeNumber: item.next_episode.number
            completed: false
          )
        ]
      } for item in shows when isNextEpisodeForItemAired(item)

    if sections.length == 0
      sections = [
        items: [
          title: "No shows to watch"
        ]
      ]
    console.log "Updating toWatch"
    @menu.section(idx, s) for s, idx in sections

menus.ToWatch = ToWatch

class MyShows
  constructor: () ->
    @menu = new UI.Menu(
      sections:[
        {
          items: [{
            title: "Loading shows..."
            }]
        }
      ]
    )

    @initHandlers()

  show: -> @menu.show()

  initHandlers: ->
    @menu.on 'select', (e) =>
      data = e.item.data
      item = i for i in @show_list when i.show.ids.trakt == data.showID
      seasonsMenu = new UI.Menu
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
        async.map(
          season.episodes,
          (ep, cb) ->
            trakttv.getOrFetchEpisodeData data.showID, data.seasonNumber, ep.number,
              (episodes) -> cb(null, episodes)
          (err, episodes) ->
            if err?
              return;
            episodesMenu = new UI.Menu
              sections: [{
                items:
                  {
                    title: episode.episodeTitle
                    subtitle: "Season #{episode.seasonNumber} Ep. #{episode.episodeNumber}"
                    data:
                      episodeTitle: episode.episodeTitle
                      overview: episode.overview
                      seasonNumber: episode.seasonNumber
                      episodeNumber: episode.episodeNumber
                      showID: episode.showID
                      showTitle: episode.showTitle
                  } for episode in episodes
              }]
            episodesMenu.show()
            episodesMenu.on 'select', (e) ->
              data = e.item.data
              detailedItemCard = new UI.Card(
                title: data.showTitle
                subtitle: "Season #{data.seasonNumber} Ep. #{data.episodeNumber}"
                body: "Title: #{data.episodeTitle}\n\
                       Overview: #{data.overview}"
                style: 'small'
                scrollable: true
              )
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
        } for item in @show_list
    ]

    @menu.section(idx, s) for s, idx in sections
    console.log "showsMenu updated"

menus.MyShows = MyShows

class Upcoming
  constructor: (opt)->
    @daysWindow = opt.days || 7;
    @fromDate = moment(opt.fromDate).format('YYYY-MM-DD')
    @userDateFormat = opt.userDateFormat || "D MMMM YYYY"

    @menu = new UI.Menu(
      sections:[
        {
          items: [{
            title: "Loading Calendar..."
            }]
        }
      ]
    )

    if Settings.data('calendar')?
      @update()

    @initHandlers()
    @reload()

  update: () ->
    # console.log "Updating UpcomingMenu: #{JSON.stringify calendar}"
    sections =
      {
        title: moment(date).format(@userDateFormat)
        items:
          {
            title: item.show.title
            subtitle: "S#{item.episode.season}E#{item.episode.number} | #{moment(item.airs_at).format('HH:MM')}"
            data:
              showID: item.show.ids.trakt
              seasonNumber: item.episode.season
              episodeNumber: item.episode.number

          } for item in items when moment(item.airs_at).isAfter(@fromDate)
      } for date, items of Settings.data 'calendar'

    # console.log "---- #{JSON.stringify sections}"

    @menu.section(idx, s) for s, idx in sections
    # sections.forEach (s, idx) => @menu.section(idx, s)

  reload: ->
    trakttv.request "/calendars/shows/#{@fromDate}/#{@daysWindow}",
      (response, status, req) =>
        Settings.data 'calendar': response
        @update()
      (response, status, req) =>
        console.log "Failed to fetch the calendar"


  show: ->
    @menu.show()

  initHandlers: ->
    @menu.on 'select', (e) ->
      element = e.item
      data = element.data
      trakttv.getOrFetchEpisodeData data.showID, data.seasonNumber, data.episodeNumber, (episode) ->
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

menus.Upcoming = Upcoming

module.exports = menus
