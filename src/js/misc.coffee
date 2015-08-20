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

colorsAvailable = Pebble.getActiveWatchInfo?().platform == "basalt"

module.exports =
  merge: merge
  uniqBy: uniqBy
  colorsAvailable: colorsAvailable
