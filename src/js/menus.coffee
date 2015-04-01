UI = require('ui')
trakttv = require('trakttv')
async = require('async')

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

class ToWatchMenu extends UI.Menu
  constructor: (opt) ->
    @icons = opt.icons
    @menu = new UI.Menu(
      sections:[
        {
          items: [{}]
        }
      ]
    )

    @initHandlers()

  show: -> @menu.show

  initHandlers: () ->
    @menu.on 'longSelect', (e) ->
      element = e.item
      data = e.item.data
      data.previousSubtitle = element.subtitle

      element.subtitle =
        if element.data.completed
          "Unchecking..."
        else
          "Checking..."

      @menu.item(e.sectionIndex, e.itemIndex, element)

      @_modifyCheckState
        showID: data.showID
        episodeNumber: data.episodeNumber
        seasonNumber: data.seasonNumber
        completed: not data.completed
        () ->
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
            reloadShow data.showID, (reloadedShow) ->
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

  _modifyCheckState: (opt, success, failure) ->
    # console.log("Check watched! episode: #{JSON.stringify(episode)}")
    console.log "checkWatched: opt: #{JSON.stringify opt}"
    if opt.episodeNumber? and not opt.seasonNumber?
      failure()
      return

    opt.completed ?= true

    request =
      shows: [
        ids: trakt: opt.showID
        seasons: [{
          number: opt.seasonNumber
          episodes: [{
            number: opt.episodeNumber
          }] if opt.episodeNumber
        }] if opt.seasonNumber
      ]

    action = if opt.completed
      '/sync/history/remove'
    else
      '/sync/history'

    # console.log "request: #{JSON.stringify request}"
    trakttv.request
      action: action
      method: 'POST'
      data: request
      (response, status, req) ->
        console.log "Check succeeded: req: #{JSON.stringify request}"
        console.log "response: #{JSON.stringify response}"
        # console.log "#{index}: #{key}: #{value}" for key, value of index for index in shows
        for item in shows when item.show.ids.trakt == opt.showID
          for season in item.seasons when not opt.seasonNumber? or season.number == opt.seasonNumber
            for episode in season.episodes when not opt.episodeNumber? or episode.number == opt.episodeNumber
              episode.completed = opt.completed
              console.log "Marking as seen #{item.show.title} S#{season.number}E#{episode.number}, #{episode.completed}"
        success()
      (response, status, req) ->
        console.log "Check FAILURE"
        failure(response, status, req)

  _createItem: (opt) ->
    for key in ['showID', 'episodeTitle', 'seasonNumber', 'episodeNumber', 'completed']
      unless opt[key]?
        console.log "ERROR: #{key} not in #{JSON.stringify opt}"
        return
    console.log "opt.completed: #{opt.completed}"
    console.log "icon chosed: " + JSON.stringify @icons
    {
      title: opt.episodeTitle
      subtitle: "Season #{opt.seasonNumber} Ep. #{opt.episodeNumber}"
      icon: if opt.completed then @icons.checked else @icons.unchecked
      data:
        showID: opt.showID
        episodeNumber: opt.episodeNumber
        seasonNumber: opt.seasonNumber
        completed: opt.completed
        isNextEpisodeListed: opt.isNextEpisodeListed
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
    @menu.sections sections

menus.ToWatchMenu = ToWatchMenu

menus.shows = {}

model = {}

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

menus.shows.updateShowsMenu = (menu, show_list) ->

  sortedShows = show_list[..]
  sortedShows.sort compareByFunction (e) -> moment(e.last_watched_at)

  model.show_list = sortedShows

  sections = [
    items:
      {
        title: item.show.title
        data:
          showID: item.show.ids.trakt
      } for item in model.show_list
  ]

  menu.sections sections
  console.log "showsMenu updated"

menus.shows.createShowsMenu = () ->
  showsMenu = new UI.Menu
    sections: [
      items: [
        {
          title: "No shows"
        }
      ]
    ]

  showsMenu.on 'select', (e) ->
    data = e.item.data
    item = i for i in model.show_list when i.show.ids.trakt == data.showID
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
        (ep, callbackResult) ->
          trakttv.getOrFetchEpisodeData data.showID, data.seasonNumber, ep.number,
            (episode) -> callbackResult(null, episode)
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

  showsMenu


module.exports = menus
