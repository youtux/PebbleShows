log = require('loglevel')
Platform = require('platform')

DEFAULT_RETRY_DELAY = 5000

misc = {}

# prioritize objects on the right
misc.merge = (objects...) ->
  res = {}
  for obj in objects
    for key, value of obj
       res[key] = value
  res

misc.uniqBy = (arr, key) ->
    seen = {}
    arr.filter (item)->
      k = key(item)
      if seen.hasOwnProperty(k)
        false
      else
        seen[k] = true
        true

misc.groupBy = (arr, key) ->
  grouped = {}
  (grouped[key e] ?= []).push e for e in arr
  grouped

misc.flatten = (arr) -> Array::concat(arr...)

misc.arrayWithout = (arr, item) ->
  arr.filter (element) => element != item

misc.spawn = (func) -> window.setTimeout func, 0

misc.retry = (func, callback, times = 10, delay = DEFAULT_RETRY_DELAY) ->
  func (args...) =>
    err = args[0]
    if err
      if times == 0
        return callback err
      else
        log.error "retry: #{err}"
        log.info "retry: rescheduling in the next #{delay} ms..."
        misc.spawn () => (misc.retry func, callback, times - 1, delay)
        return
    callback args...

misc.isEmpty = (obj) ->
  for key of obj
    return false
  return true

misc.colorsAvailable = Platform.version() == "basalt"

module.exports = misc
