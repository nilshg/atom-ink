{$, $$} = require 'atom-space-pen-views'

module.exports =
  treeView: (head, children) ->
    view = $$ ->
      @div class: 'ink tree', =>
        @span class: 'icon icon-chevron-right'
        @div class: 'header gutted'
        @div class: 'body gutted'
    view.find('> .header').append head
    view.find('> .body').append child for child in children

    view.find('> .body').hide()
    view.find('> .icon').click => @toggle view
    view.find('> .header').click => @toggle view

    view

  toggle: (view) ->
    view.find('> .body').toggle()
    icon = view.find('> .icon')
    if not view.visible
      view.visible = true
      icon.removeClass 'icon-chevron-right'
      icon.addClass 'icon-chevron-down'
    else
      view.visible = false
      icon.removeClass 'icon-chevron-down'
      icon.addClass 'icon-chevron-right'
