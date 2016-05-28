# TODO: better scrolling behaviour
{throttle} = require 'underscore-plus'
{$, $$} = require 'atom-space-pen-views'
{CompositeDisposable} = require 'atom'
trees = require '../tree'
views = require '../util/views'
{div, span} = views.tags

# ## Result API
# `Result`s are DOM elements which represent the result of some operation. They
# can be created by something like
#
# ```coffeescript
# new ink.Result(ed, range, options)
# ```
# where `ed` is the current text editor and `range` is a line range compatible array,
# e.g. `[3, 4]`. `options` is an object with the mandatory field
# - `content`: DOM-node that will be diplayed inside of the `Result`.
#
# and the optional fields
# - `error`: Default `false`. If true, adds the `error`-style to the `Result`.
# - `type`:  Default `inline`, can also be `block`. Inline-`Result`s will be
# displayed after the end of the last line contained in `range`, whereas
# block-`Result`s will be displayed below it and span the whole width of
# the current editor.

metrics = ->
  if id = localStorage.getItem 'metrics.userId'
    r = require('http').get "http://data.junolab.org/hit?id=#{id}&app=ink-result"
    r.on 'error', ->

metrics = throttle metrics, 60*60*1000

module.exports =
class Result
  constructor: (@editor, [start, end], opts={}) ->
    metrics()
    opts.type ?= 'inline'
    {@type} = opts
    @disposables = new CompositeDisposable
    opts.fade = not Result.removeLines @editor, start, end
    @createView opts
    @initMarker [start, end]
    @text = @getText()
    @disposables.add @editor.onDidChange (e) => @validateText e

  fadeIn: ->
    @view.classList.add 'ink-hide'
    @timeout 20, =>
      @view.classList.remove 'ink-hide'

  createView: (opts) ->
    {content, fade, loading} = opts
    @view = document.createElement 'div'
    @view.classList.add 'ink', 'result'
    switch @type
      when 'inline'
        @view.classList.add 'inline'
        atom.config.observe 'editor.lineHeight', (h) =>
          @view.style.top = -h + 'em';
      when 'block'  then @view.classList.add 'under'
    # @view.style.pointerEvents = 'auto'
    @view.addEventListener 'mousewheel', (e) ->
      e.stopPropagation()
    # clicking on it will bring the current result to the top of the stack
    @view.addEventListener 'click', =>
      @view.parentNode.parentNode.appendChild @view.parentNode

    @disposables.add atom.commands.add @view,
      'inline-results:clear': (e) => @remove()
    fade and @fadeIn()

    if content? then @setContent content, opts
    if loading then @setContent views.render(span 'loading icon icon-gear'), opts

  setContent: (view, {error, loading}={}) ->
    while @view.firstChild?
      @view.removeChild @view.firstChild
    if error then @view.classList.add 'error' else @view.classList.remove 'error'
    if loading then @view.classList.add 'loading' else @view.classList.remove 'loading'
    @view.appendChild view

  lineRange: (start, end) ->
    [[start, 0], [end, @editor.lineTextForBufferRow(end).length]]

  initMarker: ([start, end]) ->
    @marker = @editor.markBufferRange @lineRange(start, end),
      persistent: false
    @marker.result = @
    mark = item: @view
    switch @type
      when 'inline' then mark.type = 'overlay'
      when 'block' then mark.type = 'block'; mark.position = 'after'
    @editor.decorateMarker @marker, mark
    @disposables.add @marker.onDidChange (e) => @checkMarker e

  toggleTree: ->
    trees.toggle $(@view).find('> .tree')

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

  @all: -> # TODO: scope selector
    results = []
    for item in atom.workspace.getPaneItems() when atom.workspace.isTextEditor item
      item.findMarkers().filter((m) -> m.result?).forEach (m) ->
        results.push m.result
    results

  @invalidateAll: ->
    for result in @all()
      delete result.text
      result.invalidate()

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

  @toggleCurrent: ->
    ed = atom.workspace.getActiveTextEditor()
    for sel in ed.getSelections()
      rs = @forLines ed, sel.getHeadBufferPosition().row, sel.getTailBufferPosition().row
      rs.map (r) -> r.toggleTree()

  # Commands

  @activate: ->
    @subs = new CompositeDisposable
    @subs.add atom.commands.add 'atom-text-editor:not([mini])',
      'inline:clear-current': (e) => @removeCurrent e
      'inline-results:clear-all': => @removeAll()
      'inline-results:toggle': => @toggleCurrent()

  @deactivate: ->
    @subs.dispose()
