# Next Tuesday at 6:00 a.m.
# bDay = moment('2014-05-14 09:00:00');
Settings = require('settings')
ui = require('ui')
Wakeup = require('wakeup')

# Settings.init()

bDay = moment('2015-05-14 10:00:00')
bDayBegin = moment('2015-05-14 00:00:00')
bDayEnd = moment('2015-05-15 00:00:00')

scheduleBDay = (time) ->
  console.log "Scheduling bDay: #{bDay}"
  console.log "Remaining: #{bDay.fromNow()}";
  Wakeup.schedule
    time: time.toDate()
    notifyIfMissed: true
    (e) ->
      if e.failed
        console.log('Wakeup set failed: ' + e.error)
      else
        console.log('Wakeup set! Event ID: ' + e.id)
        Settings.data 'bDay': {set: true, id: e.id}


showBDayWindow = () ->
  cake = "\ud83c\udf82"
  popper = "\ud83c\udf89"
  bDayCard = new ui.Card
    title: "#{popper} Developer's Birthday! #{popper}"
    body: "Today is the birthday of Alessio Bogon, the developer
           who brought to you Pebble Shows.
           \nShow @youtux some \u2764\ufe0f!"
    style: "small"
    scrollable: true
    action:
      select: 'images/icon_dismiss.png'

  bDayCard.on 'click', 'select', (e) ->
    console.log "Deleting the event..."
    p = Settings.data('bDay') || {}
    p.dismissed = true
    Settings.data 'bDay': p
    bDayCard.hide()
  bDayCard.show()
  console.log "BDay window show'd"

checkAndShowBDay = () ->
  rightDay = moment().isAfter(bDayBegin) and moment().isBefore(bDayEnd)
  userDismissed = Settings.data('bDay')?.dismissed

  if rightDay and not userDismissed
    showBDayWindow()


bDayScheduled = Settings.data('bDay')?.id?
bDaySchedulable = moment().isBefore(bDay)
if not bDayScheduled and bDaySchedulable
  scheduleBDay(bDay)

if moment().isAfter(bDayEnd)
  Settings.data('bDay', null)

checkAndShowBDay()

