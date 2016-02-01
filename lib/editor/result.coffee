# TODO: better scrolling behaviour
{CompositeDisposable} = require 'atom'

module.exports =
class Result
  constructor: (@editor, range, opts={}) ->
    if not opts.type then opts.type = 'inline'
    @type = opts.type
    @disposables = new CompositeDisposable
    @createView opts
    @initMarker range
    @text = @getText()
    @disposables.add @editor.onDidChange (e) => @validateText e

  fadeIn: ->
    @view.classList.add 'ink-hide'
    @timeout 20, =>
      @view.classList.remove 'ink-hide'

  createView: ({error, content, fade}) ->
    @view = document.createElement 'div'
    @view.classList.add 'ink', 'result'
    switch @type
      when 'inline'
        @view.classList.add 'inline'
        @view.style.position = 'absolute'
        @view.style.top = -@editor.getLineHeightInPixels() + 'px'
        @view.style.left = '10px'
      when 'block' then @view.classList.add 'under'
    if error then @view.classList.add 'error'
    # @view.style.pointerEvents = 'auto'
    @view.addEventListener 'mousewheel', (e) ->
      e.stopPropagation()
    # clicking on it will bring the current result to the top of the stack
    @view.addEventListener 'click', =>
      @view.parentNode.parentNode.appendChild @view.parentNode

    @disposables.add atom.commands.add @view,
      'inline-results:clear': (e) => @remove()
    fade and @fadeIn()
    if content? then @view.appendChild content

  lineRange: (start, end) ->
    [[start, 0], [end, @editor.lineTextForBufferRow(end).length]]

  initMarker: ([start, end]) ->
    @marker = @editor.markBufferRange @lineRange(start, end),
      persistent: false
    @marker.result = @
    mark =
      item: @view
    switch @type
      when 'inline' then mark.type = 'overlay'
      when 'block' then mark.type = 'block'; mark.position = 'after'
    @editor.decorateMarker @marker, mark
    @disposables.add @marker.onDidChange (e) => @checkMarker e

  remove: ->
    @view.classList.add 'ink-hide'
    @timeout 200, => @destroy()

  destroy: ->
    @marker.destroy()
    @disposables.dispose()

  invalidate: ->
    @view.classList.add 'invalid'
    @invalid = true

  validate: ->
    @view.classList.remove 'invalid'
    @invalid = false

  checkMarker: (e) ->
    if !e.isValid or @marker.getBufferRange().isEmpty()
      @remove()
    else if e.textChanged
      old = e.oldHeadScreenPosition
      nu = e.newHeadScreenPosition
      if old.isLessThan nu
        text = @editor.getTextInRange([old, nu])
        if text.match /^\r?\n\s*$/
          @marker.setHeadBufferPosition old

  validateText: ->
    text = @getText()
    if @text == text and @invalid then @validate()
    else if @text != text and !@invalid then @invalidate()

  # Utilities

  timeout: (t, f) -> setTimeout f, t

  getText: ->
    @editor.getTextInRange(@marker.getBufferRange()).trim()

  # Bulk Actions

  @forLines: (ed, start, end, type = 'any') ->
    ed.findMarkers().filter((m) -> m.result? &&
                                   m.getBufferRange().intersectsRowRange(start, end) &&
                                  (m.result.type == type || type == 'any'))
                    .map((m) -> m.result)

  @removeLines: (ed, start, end, type = 'any') ->
    rs = @forLines(ed, start, end, type)
    rs.map (r) -> r.remove()
    rs.length > 0

  @removeAll: (ed = atom.workspace.getActiveTextEditor()) ->
    ed?.findMarkers().filter((m) -> m.result?).map((m) -> m.result.remove())

  @removeCurrent: (e) ->
    if (ed = atom.workspace.getActiveTextEditor())
      for sel in ed.getSelections()
        if @removeLines(ed, sel.getHeadBufferPosition().row, sel.getTailBufferPosition().row)
          done = true
    e.abortKeyBinding() unless done

  # Commands

  @activate: ->
    @subs = new CompositeDisposable
    @subs.add atom.commands.add 'atom-text-editor:not([mini])',
      'inline-results:clear-current': (e) => @removeCurrent e
      'inline-results:clear-all': => @removeAll()
      'inline-results:toggle': => @toggleCurrent()

  @deactivate: ->
    @subs.dispose()
