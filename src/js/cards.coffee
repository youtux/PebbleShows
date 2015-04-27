UI = require('ui')

cards = {}

cards.notification = (text, title = "Notification") ->
  card = new UI.Card
    subtitle: title
    body: text

cards.noEscape = (opt) ->
  card = new UI.Card(opt)

  card.on 'click', 'back', -> null
  return card

module.exports = cards
