UI = require('ui')

lookAndFeel = require('lookAndFeel')
misc = require('misc')

class Notification
  constructor: (cardDef) ->
    @card = createDefaultCard cardDef


  flash: (milliseconds = lookAndFeel.TIMEOUT_CARD_NOTIFICATION) ->
    @card.show()
    window.setTimeout(
      => @card.hide(),
      milliseconds
    )

  show: -> @card.show()

  hide: -> @card.hide()

flashError = (err) ->
  CRYING_FACE = "\uD83D\uDE22"
  new Notification(
    title: "Ooops #{CRYING_FACE}"
    titleColor: 'white'
    subtitle: 'Error'
    body: err.message
    style: 'large'
  ).flash()

createDefaultCard = (cardDef = {}) ->
  new UI.Card misc.merge lookAndFeel.cardDefaults, cardDef

noEscape = (cardDef) ->
  card = createDefaultCard(cardDef)
  card.on 'click', 'back', ->

  card

module.exports =
  Notification: Notification
  flashError: flashError
  createDefaultCard: createDefaultCard
  noEscape: noEscape
