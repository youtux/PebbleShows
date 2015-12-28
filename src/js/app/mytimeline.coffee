log = require('loglevel')

misc = require('misc')

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
    if not Pebble.timelineSubscriptions
      return
    return @userTopics if @userTopics

    misc.retry timelineSubscriptions, (err, subscribedTopics) =>
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
        misc.spawn () => @updateSubscriptions topics
      return

    topicsToSubscribe = topics.filter (t) => t not in @userTopics
    topicsToUnsubscribe = @userTopics.filter (t) => t not in topics

    topicsToSubscribe.forEach (topic) =>
      log.info "Subscribing to #{topic}"
      misc.retry(
        (cb) => timelineSubscribe topic, cb
        (err) =>
          return log.error(err) if err
          log.info "Subscribed to #{topic}"
          @userTopics.push topic
      )

    topicsToUnsubscribe.forEach (topic) =>
      log.info "Unsubscribing from #{topic}"
      misc.retry(
        (cb) => timelineUnsubscribe topic, cb
        (err) =>
          return log.error(err) if err
          log.info "Unsubscribed from #{topic}"
          @userTopics = misc.arrayWithout @userTopics, topic
      )

module.exports = MyTimeline
