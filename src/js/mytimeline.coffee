log = require('loglevel')

misc = require('misc')

RETRY_DELAY = 1000

spawn = (func) -> window.setTimeout func, 0

retry = (func, callback, times = 10, delay = RETRY_DELAY) ->
  func (args...) =>
    err = args[0]
    if err
      if times == 0
        return callback err
      else
        log.error "retry: #{err}"
        log.info "retry: rescheduling in the next #{delay} ms..."
        spawn () => (retry func, callback, times - 1, delay)
        return
    callback args...

timelineSubscribe = (topic, callback) ->
  Pebble.timelineSubscribe topic,
    () => callback null
    (err) => callback (new Error(err))

timelineUnsubscribe = (topic, callback) ->
  Pebble.timelineUnsubscribe topic,
    () => callback null
    (err) => callback (new Error(err))

timelineSubscriptions = (callback) =>
  Pebble.timelineSubscriptions(
    (topics) => callback null, topics
    (err) => callback (new Error(err))
  )

class MyTimeline
  @getUserTopics: (callback) =>
    return @userTopics if @userTopics

    retry timelineSubscriptions, (err, subscribedTopics) =>
      return callback(err) if err

      @userTopics = subscribedTopics
      log.info "Current timeline subscriptions: #{JSON.stringify @userTopics}"
      callback null, @userTopics

  @updateSubscriptions: (topics) =>
    if not Pebble.timelineSubscriptions
      return

    if not @userTopics
      @getUserTopics (err) =>
        return log.error(err) if err
        spawn () => @updateSubscriptions topics
      return

    topicsToSubscribe = topics.filter (t) => t not in @userTopics
    topicsToSubscribe.forEach (topic) =>
      log.info "Subscribing to #{topic}"
      retry(
        (cb) => timelineSubscribe topic, cb
        (err) =>
          return log.error(err) if err
          log.info "Subscribed to #{topic}"
          @userTopics.push topic
      )

    topicsToUnsubscribe = @userTopics.filter (t) => t not in topics
    topicsToUnsubscribe.forEach (topic) =>
      log.info "Unsubscribing from #{topic}"
      retry(
        (cb) => timelineUnsubscribe topic, cb
        (err) =>
          return log.error(err) if err
          log.info "Unsubscribed from #{topic}"
          @userTopics = misc.arrayWithout @userTopics, topic
      )

module.exports = MyTimeline
