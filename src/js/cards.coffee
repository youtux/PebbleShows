UI = require('ui')

lookAndFeel = require('lookAndFeel')
misc = require('misc')

CRYING_FACE = "\uD83D\uDE22"

class Default
  constructor: (cardDef, noEscape = false) ->
    @card = new UI.Card misc.merge lookAndFeel.cardDefaults, cardDef
    if noEscape
      @card.on 'click', 'back', ->

  flash: (milliseconds = lookAndFeel.TIMEOUT_CARD_NOTIFICATION) ->
    @card.show()
    window.setTimeout(
      => @card.hide(),
      milliseconds
    )

  show: -> @card.show()

  hide: -> @card.hide()

class Notification extends Default
  constructor: (cardDef, noEscape = false) ->
    super(
      misc.merge(
        title: 'Info'
        titleColor: 'white'
        subtitleColor: 'white'
        style: 'large'
        cardDef
      )
      noEscape
    )

  @fromMessage: (message, title = 'Info') ->
    new Notification(
      title: title
      body: message
    )

class Error extends Notification
  @_defaultTitle: "Ooops #{CRYING_FACE}"
  constructor: (cardDef, noEscape = false) ->
    super(
      misc.merge(
        title: Error._defaultTitle
        cardDef
      )
      noEscape
    )

  @fromError: (err) ->
    @fromMessage err.message

  @fromMessage: (message, title = @_defaultTitle) ->
    new Error(
      title: title
      body: message
    )


flashError = (err) ->
  Error.fromError(err).flash()

module.exports =
  Default: Default
  Notification: Notification
  Error: Error
  flashError: flashError
