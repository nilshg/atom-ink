# TODO: invalid results don't fade out
# In general this is weird and needs a refactor
# TODO: fade results when the cursor is underneath
# TODO: better scrolling behaviour

{CompositeDisposable} = require 'atom'

module.exports =
  activate: ->
    @subs = new CompositeDisposable()
    @monotypeResults = atom.config.get('ink.monotypeResults')
    @subs.add atom.commands.add 'atom-text-editor:not([mini])',
      'inline-results:clear-current': (e) => @removeCurrent e
      'inline-results:clear-all': => @removeAll()
      'inline-results:toggle': => @toggleCurrent()
      'inline-results:copy-current': => @copyCurrent()

    @subs.add atom.commands.add '.ink.inline',
      'inline-results:clear': (e) ->
        result = e.currentTarget.result
        setTimeout (-> result.destroy()), 0
      'inline-results:copy': (e) ->
        atom.clipboard.write(e.currentTarget.result.view.getAttribute('plain'))

  deactivate: ->
    @subs.dispose()

  timeout: (t, f) -> setTimeout f, t

  result: (ed, content, {error, clas, plainresult}) ->
    view = document.createElement 'div'
    view.classList.add 'ink', 'inline', 'result'
    if error then view.classList.add 'error'
    if clas then view.classList.add clas
    if plainresult then view.setAttribute 'plain', plainresult
    if @monotypeResults then view.style.font = 'inherit'
    view.style.position = 'absolute'
    view.style.top = -ed.getLineHeightInPixels() + 'px'
    view.style.left = '10px'
    view.style.pointerEvents = 'auto'
    view.appendChild content
    view: view

  methods: (r) ->
    r.view.result = r
    r.destroy = => @remove r
    r.invalidate = => @invalidate r
    r.validate = => @validate r

  show: (ed, mark, {watch, content, error, clas, plainresult}={}) ->
    mark.getBufferRange().isReversed and throw "Cannot add result to reversed marker"
    flag = @removeLines ed, mark.getHeadBufferPosition().row,
                            mark.getTailBufferPosition().row
    result = @result ed, content, {error, clas, plainresult}
    mark.result = result
    result.editor = ed
    result.marker = mark
    result.text = @text result
    result.decorator = ed.decorateMarker mark,
      type: 'overlay'
      item: result.view
    # TODO: clean some of this up. It probably belongs in a constructor
    @methods result
    result.view.addEventListener 'click', =>
      result.view.parentNode.parentNode.appendChild result.view.parentNode
    result.view.addEventListener 'mousewheel', (e) ->
      e.stopPropagation()
    if !flag
      result.view.classList.add 'ink-hide'
      @timeout 20, =>
        result.view.classList.remove 'ink-hide'
    watch != false and @watchText result
    @watchNewline result
    result

  lineRange: (ed, start, end) ->
    [[start, 0], [end, ed.lineTextForBufferRow(end).length]]

  showForRange: (ed, range, opts) ->
    mark = ed.markBufferRange range
    result = @show ed, mark, opts
    result.ownsMark = true
    return result

  showForLines: (ed, start, end, opts) ->
    @showForRange ed, @lineRange(ed, start, end), opts

  remove: (result) ->
    result.view.classList.add 'ink-hide'
    @timeout 200, =>
      result.decorator.destroy()
      result.ownsMark and result.marker.destroy()
      result.editorWatch?.dispose()
      result.newlineWatch?.dispose()

  invalidate: (result) ->
    result.view.classList.add 'invalid'
    result.invalid = true

  validate: (result) ->
    result.view.classList.remove 'invalid'
    result.invalid = false

  text: ({editor, marker}) ->
    editor.getTextInRange(marker.getBufferRange()).trim()

  watchText: (r) ->
    r.editWatch = r.editor.onDidChange => @checkText r

  checkText: (r) ->
    text = @text r
    if r.text == text and r.invalid then r.validate()
    else if r.text != text and !r.invalid then r.invalidate()

  watchNewline: (r) ->
    r.newlineWatch = r.marker.onDidChange (e) => @checkNewline r, e

  checkNewline: (r, e) ->
    if !e.isValid or r.marker.getBufferRange().isEmpty()
      r.destroy()
    else if e.textChanged
      old = e.oldHeadScreenPosition
      nu = e.newHeadScreenPosition
      text = r.editor.getTextInRange([old, nu])
      if old.isLessThan(nu) && text.match /^\r?\n\s*$/
        r.marker.setHeadBufferPosition old

  forLines: (ed, start, end) ->
    ed.findMarkers().filter((m)->m.result? &&
                                 m.getBufferRange().intersectsRowRange(start, end))
                    .map((m)->m.result)

  removeLines: (ed, start, end) ->
    flag = false
    for r in @forLines ed, start, end
      flag = true
      r.destroy()
    flag

  removeAll: (ed) ->
    ed ?= atom.workspace.getActiveTextEditor()
    for r in ed.findMarkers().filter((m)->m.result?).map((m)->m.result)
      r.destroy()

  removeCurrent: (e) ->
    ed = e.currentTarget.getModel()
    for sel in ed.getSelections()
      if @removeLines(ed, sel.getHeadBufferPosition().row, sel.getTailBufferPosition().row)
        done = true
    e.abortKeyBinding() unless done

  getCurrentMarkers: ->
    ed = atom.workspace.getActiveTextEditor()
    pos = ed.getCursorBufferPosition()
    ms = ed.findMarkers {containsBufferPosition: pos}
    ms = ms.filter((m)->m.result?).map((m)->m.result)

  toggleCurrent: ->
    ms = @getCurrentMarkers()
    ms.map((m) -> m?.view.firstElementChild?.firstElementChild?.click())

  copyCurrent: ->
    m = @getCurrentMarkers()[0]
    atom.clipboard.write(m.view.getAttribute('plain'))
