UI = require('ui')

cards = {}

class Notification
  constructor: (text, title = "Notification") ->
    @card = new UI.Card(
      subtitle: title
      body: text
    )

  flash: (milliseconds = 3000) ->
    @card.show()
    window.setTimeout(
      => @card.hide(),
      milliseconds
    )

  show: -> @card.show()

  hide: -> @card.hide()

flashError = (err) ->
  new Notification(err.message, "Error").flash()

cards.Notification = Notification

cards.noEscape = (opt) ->
  card = new UI.Card(opt)

  card.on 'click', 'back', -> null
  return card

module.exports = cards
