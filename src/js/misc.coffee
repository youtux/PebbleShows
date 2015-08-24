Platform = require('platform')

DEFAULT_RETRY_DELAY = 5000

# prioritize objects on the right
merge = (objects...) ->
  res = {}
  for obj in objects
    for key, value of obj
       res[key] = value
  res

uniqBy = (arr, key) ->
    seen = {}
    arr.filter (item)->
      k = key(item)
      if seen.hasOwnProperty(k)
        false
      else
        seen[k] = true
        true

groupBy = (arr, key) ->
  grouped = {}
  (grouped[key e] ?= []).push e for e in arr
  grouped

flatten = (arr) -> Array::concat(arr...)

arrayWithout = (arr, item) ->
  arr.filter (element) => element != item

spawn = (func) -> window.setTimeout func, 0

retry = (func, callback, times = 10, delay = DEFAULT_RETRY_DELAY) ->
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

colorsAvailable = Platform.version() == "basalt"

module.exports =
  merge: merge
  uniqBy: uniqBy
  groupBy: groupBy
  flatten: flatten
  arrayWithout: arrayWithout
  colorsAvailable: colorsAvailable
  spawn: spawn
  retry: retry
