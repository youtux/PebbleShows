ajax = require('ajax')
timeline = {}

timeline.BASE_URL = 'https://pebbleshows.herokuapp.com'

timeline.subscribe = (topic) ->
  Pebble.timelineSubscribe "#{topic}",
    -> console.log('Subscribed to ' + "#{topic}")
    (error) -> console.log('Error subscribing to topic: ' + error)

timeline.getLaunchData = (launchCode, cb) ->
  console.log "getLaunchData url: #{@BASE_URL}/api/getLauchData/#{launchCode}"
  ajax
    url: "#{@BASE_URL}/api/getLaunchData/#{launchCode}"
    type: 'json'
    (data, status, request) ->
      console.log("GOT DATA: #{JSON.stringify data}")
      cb(null, data)
    (err, status, request) ->
      console.log("GOT error: #{JSON.stringify err}")
      cb(err, status, request)


module.exports = timeline
