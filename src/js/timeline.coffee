ajax = require('ajax')

config = require('config')

timeline = {}

timeline.subscribe = (topic) ->
  retryPeriod = 5000
  Pebble.timelineUnsubscribe "#{topic}",
    -> console.log('Subscribed to ' + "#{topic}")
    (error) ->
      console.log('Error subscribing to topic: ' + error)
      console.log("Retrying in #{retryPeriod / 1000} seconds")
      setTimeout(
        -> Pebble.timelineSubscribe "#{topic}",
        retryPeriod
      )

timeline.getLaunchData = (launchCode, cb) ->
  console.log "getLaunchData url: #{config.BASE_SERVER_URL}/api/getLaunchData/#{launchCode}"
  ajax
    url: "#{config.BASE_SERVER_URL}/api/getLaunchData/#{launchCode}"
    type: 'json'
    (data, status, request) ->
      console.log("GOT DATA: #{JSON.stringify data}")
      cb(null, data)
    (err, status, request) ->
      console.log("GOT error: #{JSON.stringify err}")
      cb(err, status, request)


module.exports = timeline
