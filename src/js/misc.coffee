Platform = require('platform')

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

colorsAvailable = Platform.version() == "basalt"

module.exports =
  merge: merge
  uniqBy: uniqBy
  groupBy: groupBy
  flatten: flatten
  arrayWithout: arrayWithout
  colorsAvailable: colorsAvailable
