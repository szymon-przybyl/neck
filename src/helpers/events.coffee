### LIST OF EVENTS TO TRIGGER ###

EventList = [
  # Mouse events
  "click", "dblclick"
  "mouseenter", "mouseleave", "mouseout"
  "mouseover", "mousedown", "mouseup"
  "drag", "dragstart", "dragenter", "dragleave", "dragover", "dragend", "drop"
  # General
  "load"
  "focus", "focusin", "focusout", "select", "blur"
  "submit"
  "scroll"
  # Touch events
  "touchstart", "touchend", "touchmove", "touchenter", "touchleave", "touchcancel"
  # Keys events
  "keyup", "keydown", "keypress"
]

class EventHelper extends Neck.Helper
  constructor: (opts)->
    super
    
    if typeof @scope._main is 'function'
      @scope._main.call @scope._context, opts.e

    @off()
    @stopListening()

class Event
  template: false
  
  constructor: (options)->
    # Anchor should have 'href' attribute
    if options.el[0].tagName is 'A'
      options.el.attr 'href', '#'

    options.el.on @eventType, (e)=>
      e.preventDefault()
      options.e = e
      new EventHelper options

for ev in EventList
  helper = class ER extends Event
  helper::eventType = ev
  Neck.Helper[Neck.Tools.dashToCamel("event-#{ev}")] = helper