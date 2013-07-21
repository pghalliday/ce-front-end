module.exports = class Relationship
	constructor: (params) ->
    if params && params.name
      @name = params.name
      @verbs = {}
    else
      throw new Error 'Must specify the relationship name'

  verb: (params) =>
    if params && params.name
      @verbs[params.name] =
        request: params.request
        response: params.response
      return @
    else
      throw new Error 'Must specify the verb name'