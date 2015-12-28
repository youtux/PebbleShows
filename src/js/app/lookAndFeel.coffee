misc = require('misc')

TIMEOUT_SUBTITLE_NOTIFICATION = 2000
TIMEOUT_CARD_NOTIFICATION = 4000

colors =
  if misc.colorsAvailable
    backgroundColor: 'oxfordBlue'
    textColor: 'white'
    thirdColor: 'orange'
  else
    backgroundColor: 'white'
    textColor: 'black'

menuDefaults = misc.merge(
  {
    textColor: colors.textColor
    backgroundColor: colors.backgroundColor
    fullscreen: false
  }
  if misc.colorsAvailable
    highlightBackgroundColor: colors.thirdColor
    highlightTextColor: 'white'
  else
    highlightBackgroundColor: colors.textColor
    highlightTextColor: colors.backgroundColor
)

cardDefaults = misc.merge(
  {
    textColor: colors.textColor
    backgroundColor: colors.backgroundColor
    bodyColor: colors.textColor
    fullscreen: false
    style: 'small'
    scrollable: true
  }
  if misc.colorsAvailable
    titleColor: colors.thirdColor
    subtitleColor: colors.thirdColor
  else
    titleColor: colors.textColor
    subtitleColor: colors.textColor
)


module.exports =
  colors: colors
  menuDefaults: menuDefaults
  cardDefaults: cardDefaults
  TIMEOUT_SUBTITLE_NOTIFICATION: TIMEOUT_SUBTITLE_NOTIFICATION
  TIMEOUT_CARD_NOTIFICATION: TIMEOUT_CARD_NOTIFICATION

