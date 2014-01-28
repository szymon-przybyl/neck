window.Neck = Neck = {}

# Add "ui-hide" class
$('''
  <style media="screen">
    .ui-hide { display: none !important }
  </style>
  ''').appendTo $('head')

Neck.Tools =
  dashToCamel: (str)-> str.replace /\W+(.)/g, (x, chr)-> chr.toUpperCase()
  camelToDash: (str)-> str.replace(/\W+/g, '-').replace(/([a-z\d])([A-Z])/g, '$1-$2')

Neck.DI =
  controllerPrefix: 'controllers'
  helperPrefix: 'helpers'
  templatePrefix: 'templates'

  _routePath: /^([a-zA-Z$_\.]+\/?)+$/i

  load: (route, options)-> 
    if route.match @_routePath
      try
        return require (if options.type then @[options.type + 'Prefix'] + "/" else '') + route
      catch
        if window[route]
          return window[route]
        else if options.type isnt 'template'
          return throw "No defined '#{route}' object for Neck dependency injection"

    route
      

class Neck.Controller extends Backbone.View  
  REGEXPS:
    TEXTS: /\'[^\']+\'/g
    RESERVED_KEYWORDS: new RegExp """
      ^(do|if|in|for|let|new|try|var|case|else|enum|eval|false|null|this|true|
      void|with|break|catch|class|const|super|throw|while|yield|delete|export|import|public|
      return|static|switch|typeof|default|extends|finally|package|private|continue|debugger|
      function|arguments|interface|protected|implements|instanceof|undefined|window)($|\.)"""
    SCOPE_PROPERTIES: /([a-zA-Z$_\@][^\ \[\]\:\(\)\{\}]*)/g
    TWICE_SCOPE: /(scope\.[^\ ]*\.)scope\./
    EXPRESSION: /[-+=\(\)\{\}\:]+/
    METHOD: /[a-zA-Z$_][^\ \(\)\{\}\:]*\(/
    OBJECT: /^\{.+\}$/g
    ONLY_PROPERTY: /^[a-zA-Z$_][^\ \(\)\{\}\:]*$/g
    SLASHES: /\//g

  divWrapper: true
  template: false
  
  constructor: (opts)->
    super

    # Create scope inherit or new
    scope = if @parent = opts?.parent then Object.create(@parent.scope) else _context: @
    @scope = _.extend scope, @scope, _resolves: {}

    # Listen to parent events
    if @parent
      @listenTo @parent, 'remove', @remove
      @listenTo @parent, 'clear', @clear

    @template = opts.template if opts.template

    if @template is true
      @template = @$el.html()
      @$el.empty()

    @params = opts.params or {}

  remove: =>
    @trigger 'remove'

    # Clear references
    @parent = undefined
    @scope = undefined

    # Trigger Backbone remove 
    super

  clear: =>
    @trigger 'clear'
    @off()
    @stopListening()

  render: ->
    @trigger 'clear' # Remove childs listings

    if @template
      if typeof (template = Neck.DI.load(@template, type: 'template')) is 'function'
        template = template @scope
    
      if @divWrapper
        @$el.html template
      else
        @setElement $(template)
    
    for el in @$el
      @_parseNode el 

    @

  _parseNode: (node)->
    if node?.attributes
      el = null
      for attribute in node.attributes
        if attribute.nodeName?.substr(0, 3) is "ui-"
          el or= $(node)
          name = Neck.Tools.dashToCamel attribute.nodeName.substr(3)
          helper = new (Neck.Helper[name] or Neck.DI.load(name, type: 'helper'))(el: el, parent: @, mainAttr: attribute.value)
          stop = true if helper.template isnt false
    
    @_parseNode child for child in node.childNodes unless stop or not node
    undefined

  _parseValue: (s)->
    s = s.trim()
    texts = []
    resolves = []

    # Replace texts for recognition
    s = s.replace @REGEXPS.TEXTS, (t)-> 
      texts.push t
      "###"

    # Find scope properties
    s = s.replace @REGEXPS.SCOPE_PROPERTIES, (t)=>
      unless t.match @REGEXPS.RESERVED_KEYWORDS
        unless t.substr(0, 1) is '@'
          resolves.push t.split('.')[0]
        else
          t = '_context.' + t.substr(1)
        "scope.#{t}"
      else
        t

    # Clear twice 'scope'
    while s.match @REGEXPS.TWICE_SCOPE
      s = s.replace @REGEXPS.TWICE_SCOPE, "$1"
 
    # Unreplace texts
    if texts.length
      s = s.replace(/###/g, ()-> texts.shift()) 

     # Add brackets when string is object instance
    if s.match @REGEXPS.OBJECT
      s = "(#{s})"

    [s, _.uniq resolves]

  _setAccessor: (key, value, controller = @parent)->
    scope = controller.scope
    [value, resolves] = @_parseValue value

    options = enumerable: true, get: -> 
      try
        eval value
      catch e
        undefined

    if value.match @REGEXPS.EXPRESSION
      options.get = =>
        try
          eval value
          @apply key
        catch e
          undefined

    if value.match @REGEXPS.ONLY_PROPERTY
      options.set = (newVal)=>
        model = value.split('.')
        property = model.pop()
        
        # # Create objects when they are undefined
        obj = scope
        for m in model.slice(1)
          obj = obj[m] = {} unless obj[m]

        try
          (eval model.join('.'))[property] = newVal
          @apply key if model.length > 1
        catch e
          undefined
    
    Object.defineProperty @scope, key, options

    if controller isnt @
      @scope._resolves[key] = []
      for resolve in resolves
        if controller.scope._resolves[resolve]
          @scope._resolves[key] = _.union @scope._resolves[key], controller.scope._resolves[resolve]
        else
          @scope._resolves[key].push { controller: controller, key: resolve }
      # Clear when empty
      unless @scope._resolves[key].length
        @scope._resolves[key] = undefined

  _watch: (key, callback, context = @)->
    if @scope.hasOwnProperty(key) or !@parent
      if Object.getOwnPropertyDescriptor(@scope, key)?.get
        if @scope._resolves[key]
          for resolve in @scope._resolves[key]
            resolve.controller._watch resolve.key, callback, context
          undefined
        else
          context.listenTo @, "refresh:#{key}", callback
      else
        val = @scope[key]

        if val instanceof Backbone.Model
          @listenTo val, "sync", => @apply key

        Object.defineProperty @scope, key, 
          enumerable: true
          get: -> val
          set: (newVal)=>
            if val instanceof Backbone.Model
              @stopListening val
            if newVal instanceof Backbone.Model  
              @listenTo newVal, "sync", => @apply key
              
            val = newVal
            @apply key
      
        context.listenTo @, "refresh:#{key}", callback
    else
      controller = @
      while controller = controller.parent
        if controller.scope.hasOwnProperty key
          controller._watch key, callback, context
          break
      undefined

  watch: (keys..., callback)->
    call = => callback.apply @, _.map keys, (k)=> @scope[k]
    @_watch key.split('.')[0], call for key in keys
    call()

  apply: (key)->
    if @scope._resolves[key]
      for resolve in @scope._resolves[key]
        resolve.controller.trigger "refresh:#{resolve.key}"
      undefined
    else
      @trigger "refresh:#{key}"

class Neck.Helper extends Neck.Controller

  constructor: (opts)->
    super
    @_setAccessor '_main', opts.mainAttr

    if @attributes
      for attr in @attributes
        if value = @el.attributes[Neck.Tools.camelToDash(attr)]?.value
          @_setAccessor attr, value