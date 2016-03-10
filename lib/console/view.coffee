class ConsoleElement extends HTMLElement

  createdCallback: ->
    @setAttribute 'tabindex', -1
    @gutter = document.createElement 'div'
    @gutter.classList.add 'gutter'
    @appendChild @gutter
    @items = document.createElement 'div'
    @items.classList.add 'items'
    @appendChild @items

    @style.fontSize = atom.config.get('editor.fontSize') + 'px'
    @style.fontFamily = atom.config.get('editor.fontFamily')

    @views = {}
    for view in ['input', 'stdout', 'stderr', 'info', 'result']
      @views[view] = this["#{view}View"].bind this

  initialize: (@model) ->
    @getModel = -> @model
    @model.onDidAddItem (item) => @addItem item
    @model.onDidInsertItem ([item, i]) => @insertItem [item, i]
    @model.onDidClear => @clear()
    @model.onDone => if @hasFocus() then @focus()
    @model.onFocusInput (force) => @focusLast force
    @model.onLoading (status) => @loading status
    @onfocus = =>
      if document.activeElement == this and @model.getInput()
        @focusLast()
    for item in @model.items
      @addItem item
    @

  getModel: -> @model

  initView: (item) ->
    item.view ?= @views[item.type](item)
    item.cell ?= @cellView item
    item

  addItem: (item) ->
    {cell} = @initView item
    @lock =>
      @items.appendChild cell
      @items.appendChild @divider()
    @loading()

  insertItem: ([item, i]) ->
    {cell} = @initView item
    before = @model.items[i+1].cell
    @lock =>
      @items.insertBefore cell, before
      @items.insertBefore @divider(), before
    @loading()

  divider: ->
    d = document.createElement 'div'
    d.classList.add 'divider'
    d

  clear: ->
    if @hasFocus() then @focus() # Don't lose focus completely when removing a
                                 # focused editor
    while @items.hasChildNodes()
      @items.removeChild @items.lastChild

  queryLast: (view, q) ->
    items = view.querySelectorAll q
    items[items.length - 1]

  lastCell: -> @queryLast @items, '.cell'

  lastDivider: -> @queryLast @items, '.divider'

  isVisible: (pane, view) ->
    if !view? then [pane, view] = [@, pane]
    return unless view?
    pane = pane.getBoundingClientRect()
    view = view.getBoundingClientRect()
    pane.bottom >= view.top >= pane.top or pane.bottom >= view.bottom >= pane.top

  focusVisible: (view, force) ->
    if force or @isVisible view
      view.focus()

  focusLast: (force) ->
    if @hasFocus() and (view = @model.items[@model.items.length-1]?.view)
      @focusVisible view, force

  # Various cell views

  observeKey: (obj, key, cb) ->
    Object.observe obj, (changes) ->
      for change in changes
        if change.name is key
          cb(change.object[key])
          return

  iconView: (name) ->
    icon = document.createElement 'span'
    icon.classList.add 'icon', 'icon-'+name
    icon

  cellView: (item) ->
    {view, icon} = item
    cell = document.createElement 'div'
    cell.classList.add 'cell'
    cell.setAttribute 'tabindex', -1

    gutter = document.createElement 'div'
    gutter.classList.add 'gutter'
    cell.appendChild gutter

    @observeKey item, 'icon', => @updateIcon item
    @updateIcon {cell, icon: item.icon}

    content = document.createElement 'div'
    content.classList.add 'content'
    content.appendChild view
    cell.appendChild content

    cell

  inputView: (item) ->
    ed = document.createElement 'atom-text-editor'
    # Wait for ed to be attached
    setTimeout (-> ed.component?.presenter.scrollPastEnd = false), 0
    item.editor = ed.getModel()
    item.editor.setLineNumberGutterVisible(false)
    @updateGrammar item
    @observeKey item, 'grammar', => @updateGrammar item
    ed

  updateGrammar: ({editor, grammar}) ->
    editor.setGrammar atom.grammars.grammarForScopeName grammar

  streamView: (item, type) ->
    out = document.createElement 'div'
    out.innerText = item.text
    @observeKey item, 'text', (text) =>
      @lock -> out.innerText = text
    out.classList.add type, 'stream'
    out

  stdoutView: (item) -> @streamView item, 'output'

  stderrView: (item) -> @streamView item, 'err'

  infoView: (item) -> @streamView item, 'info'

  resultView: ({result, error}) ->
    view = document.createElement 'div'
    view.classList.add 'result'
    if error then view.classList.add 'error'
    view.appendChild result
    view

  updateIcon: ({cell, icon}) ->
    gutter = cell.querySelector '.gutter'
    iconView = cell.querySelector '.icon'
    if iconView? then gutter.removeChild iconView
    icon2 = @iconView icon
    gutter.appendChild icon2

  hasFocus: ->
    @contains document.activeElement

  loading: (l = @isLoading) ->
    if l
      @loading false
      @lastDivider()?.classList.add 'loading'
    else
      @items.querySelector('.divider.loading')?.classList.remove 'loading'
    @isLoading = l

  # Scrolling

  lock: (f) ->
    last = @lastCell()
    if @isVisible last
      target = last.offsetTop + last.clientHeight - @scrollTop
      f()
      last = @lastCell()
      delta = last.offsetTop + last.clientHeight - @scrollTop - target
      @scrollTop += delta
    else
      f()

module.exports = ConsoleElement = document.registerElement 'ink-console', prototype: ConsoleElement.prototype
