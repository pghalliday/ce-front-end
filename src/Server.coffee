http = require 'http'
engine = require 'engine.io'
express = require 'express'

module.exports = class Server
  constructor: (@options) ->
    @expressServer = express()
    @httpServer = http.createServer @expressServer
    @engineServer = engine.attach @httpServer
    
    @expressServer.get '/', (request, response) ->
      response.send 200, 'hello'

  stop: (callback) =>
    try
      @httpServer.close callback
    catch error
      callback error

  start: (callback) =>
    @httpServer.listen @options.port, callback
