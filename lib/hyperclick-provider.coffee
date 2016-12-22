inspectPython = require './inspect-python'

module.exports =
  priority: 2

  providerName: 'inspect-python'

  getSuggestionForWord: (editor, text, range) ->
    wrappedSuggestion = inspectPython.wrappedHyperclickProvider.getSuggestionForWord(editor, text, range)
    if wrappedSuggestion
      callback = ->
        inspectPython.openDefinition(editor, range.start)
      return {range, callback}
