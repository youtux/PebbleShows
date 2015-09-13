Settings = require('settings')
Emitter = require('emitter')

Function::define = (prop, desc) ->
  Object.defineProperty this.prototype, prop, desc

class AppSettings
  constructor: ->
    @data = (Settings.data 'appSettings') or {}
    @emitter = new Emitter()

  on: (args...) -> @emitter.on(args...)

  persist: ->
    Settings.data 'appSettings', @data

  @define 'timeFormat',
    get: ->
      @data.timeFormat or '12'
    set: (value) ->
      if value != '12' and value != '24'
        throw new Error("timeFormat must be '12' or '24'")
      @data.timeFormat = value
      @persist()
      @emitter.emit 'timeFormat', timeFormat: value
  @define 'calendarDays',
    get: ->
      @data.calendarDays or 7
    set: (value) ->
      if (typeof value) != 'number'
        throw new Error('calendarDays must be a number')
      @data.calendarDays = value
      @persist()
      @emitter.emit 'calendarDays', calendarDays: value

module.exports = new AppSettings()
