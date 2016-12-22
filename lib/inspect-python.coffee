{CompositeDisposable, Point, TextEditorPresenter} = require 'atom'


monkey_patch = (model) ->
  # monkey patching to prevent strange bug,
  # see here: https://github.com/atom/atom/issues/8477
  model.presenter.updateTilesState = ->
    return unless @startRow? and @endRow? and @lineHeight?

    screenRows = @getScreenRowsToRender()
    visibleTiles = {}
    startRow = screenRows[0]
    endRow = screenRows[screenRows.length - 1]
    screenRowIndex = screenRows.length - 1
    zIndex = 0

    for tileStartRow in [@tileForRow(endRow)..@tileForRow(startRow)] by -@tileSize
      tileEndRow = tileStartRow + @tileSize
      rowsWithinTile = []

      while screenRowIndex >= 0
        currentScreenRow = screenRows[screenRowIndex]
        break if currentScreenRow < tileStartRow
        rowsWithinTile.push(currentScreenRow)
        screenRowIndex--

      continue if rowsWithinTile.length is 0

      top = Math.round(@lineTopIndex.pixelPositionBeforeBlocksForRow(tileStartRow))
      bottom = Math.round(@lineTopIndex.pixelPositionBeforeBlocksForRow(tileEndRow))
      height = bottom - top

      tile = @state.content.tiles[tileStartRow] ?= {}
      tile.top = top - @scrollTop
      tile.left = -@scrollLeft
      tile.height = height
      tile.display = "block"
      tile.zIndex = zIndex
      tile.highlights ?= {}

      gutterTile = @lineNumberGutter.tiles[tileStartRow] ?= {}
      gutterTile.top = top - @scrollTop
      gutterTile.height = height
      gutterTile.display = "block"
      gutterTile.zIndex = zIndex

      @updateLinesState(tile, rowsWithinTile)
      @updateLineNumbersState(gutterTile, rowsWithinTile)

      visibleTiles[tileStartRow] = true
      zIndex++

    mouseWheelTileId = @tileForRow(@mouseWheelScreenRow) if @mouseWheelScreenRow?

    for id, tile of @state.content.tiles
      continue if visibleTiles.hasOwnProperty(id)

      # these lines caused the bug that prevents nested editors:
      #if Number(id) is mouseWheelTileId
      #  @state.content.tiles[id].display = "none"
      #  @lineNumberGutter.tiles[id].display = "none"
      #else
      delete @state.content.tiles[id]
      delete @lineNumberGutter.tiles[id]


module.exports =
  subscriptions: null
  autocomplete_provider: null

  getHyperclickProvider: ->
    require './hyperclick-provider'

  consumeObserveTextEditor: (observeTextEditor) ->
    @observeTextEditor = observeTextEditor

  activate: (state) ->
    pythonAutocomplete = require(
      atom.packages.resolvePackagePath 'autocomplete-python'
    )
    @wrappedAutocompleteProvider = pythonAutocomplete.getProvider()
    @wrappedHyperclickProvider = pythonAutocomplete.getHyperclickProvider()
    # Events subscribed to in atom's system can be easily cleaned up with
    # a CompositeDisposable
    @subscriptions = new CompositeDisposable()

    # here subscriptions can be registered like this:
    #@subscriptions.add(atom.commands.add('atom-workspace', {
    #  'inspect-python:toggle': => @toggle()
    #}))

  deactivate: ->
    @subscriptions.dispose()

  serialize: -> {}

  make_ui: (editor, editor_elem, marker, filename) ->
    update_editor_text = ->
      editor.setText(
        editor.inspect_python_original_editor.getTextInBufferRange([
          [editor.inspect_python_start_line, 0],
          [editor.inspect_python_end_line, 200]
        ])
      )
    update_editor_text()
    close_ui = ->
      marker.destroy()
    expand_up = ->
      editor.inspect_python_start_line -= 5
      update_editor_text()
    expand_down = ->
      editor.inspect_python_end_line += 5
      update_editor_text()
    ui = document.createElement('div')
    ui.className = "inspect-python"

    close_button = document.createElement('button')
    close_button.className = "inspect-python-close"
    close_button.appendChild(document.createTextNode("X"))
    close_button.addEventListener('click', close_ui)
    titlebar = document.createElement('span')
    titlebar.className = 'inspect-python-titlebar'
    up_button = document.createElement('button')
    up_button.className = "inspect-python-expand"
    up_button.appendChild(document.createTextNode("▲"))
    titlebar.addEventListener('click', expand_up)
    title = document.createElement('span')
    title.className = "inspect-python-title"
    title.appendChild(document.createTextNode(filename))
    titlebar.appendChild(up_button)
    titlebar.appendChild(title)

    close_button2 = document.createElement('button')
    close_button2.className = "inspect-python-close"
    close_button2.appendChild(document.createTextNode("X"))
    close_button2.addEventListener('click', close_ui)
    titlebar2 = document.createElement('span')
    titlebar2.className = 'inspect-python-titlebar'
    down_button = document.createElement('button')
    down_button.className = "inspect-python-expand"
    down_button.appendChild(document.createTextNode("▼"))
    titlebar2.addEventListener('click', expand_down)
    title2 = document.createElement('span')
    title2.className = "inspect-python-title"
    title2.appendChild(document.createTextNode(filename))
    titlebar2.appendChild(down_button)
    titlebar2.appendChild(title2)

    ui.appendChild(close_button)
    ui.appendChild(titlebar)
    ui.appendChild(editor_elem)
    ui.appendChild(close_button2)
    ui.appendChild(titlebar2)
    return ui

  openDefinition: (current_editor, bufferPosition) ->
    monkey_patch current_editor
    if bufferPosition instanceof Array
      bufferPosition = Point(bufferPosition[0], bufferPosition[1])
    editor_for_search = current_editor
    position_for_search = bufferPosition
    if current_editor.inspect_python_original_editor
      editor_for_search = current_editor.inspect_python_original_editor
      position_for_search = Point(
        bufferPosition.row + current_editor.inspect_python_start_line,
        bufferPosition.column,
      )
    @wrappedAutocompleteProvider.getDefinitions(
      editor_for_search, position_for_search
    ).then (results) =>
      console.log(JSON.stringify([position_for_search, results]))
      [{line, column, text, type, fileName}] = results
      atom.workspace.open(fileName, {
        activatePane: false,
        activateItem: false,
      }).then (inspect_python_original_editor) =>
        marker = current_editor.markScreenPosition(bufferPosition)
        editor = atom.workspace.buildTextEditor()
        editor.inspect_python_original_editor = inspect_python_original_editor
        editor.inspect_python_start_line = line
        editor.inspect_python_end_line = line + 10
        editor.setGrammar(inspect_python_original_editor.getGrammar())

        editor_elem = atom.views.getView(editor)
        ui = @make_ui(editor, editor_elem, marker, fileName)
        ui.addEventListener 'click', (e) ->
          # both are needed: stopPropagation _AND_ blur() and focus()
          # with only blur() and focus() it works only for one level of nesting
          e.stopPropagation()
          atom.views.getView(current_editor).blur()
          editor_elem.focus()
        ui.addEventListener 'mousemove', (e) ->
          e.stopPropagation()

        current_editor.decorateMarker(marker, {
          type: 'block', position: 'after',
          item: ui
        })
        editor.setCursorBufferPosition([0, 0])
        editor.scrollToCursorPosition()
        @observeTextEditor(editor)
