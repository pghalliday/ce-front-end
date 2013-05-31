engine = require 'engine.io'
http = require 'http'

module.exports = class Server
  constructor: (@options) ->
    @httpServer = http.createServer()
    @engineServer = engine.attach @httpServer

  stop: (callback) =>
    try
      @httpServer.close callback
    catch error
      callback error

  start: (callback) =>
    @httpServer.listen @options.port, callback
