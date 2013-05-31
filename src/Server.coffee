http = require 'http'
engine = require 'engine.io'
express = require 'express'
zmq = require 'zmq'
uuid = require 'node-uuid'

module.exports = class Server
  constructor: (@options) ->
    @connections = []
    @engineConnections = {}
    @expressServer = express()
    @httpServer = http.createServer @expressServer
    @engineServer = engine.attach @httpServer
    @ceOperationHub = zmq.socket 'req'

    @httpServer.on 'connection', (connection) =>
      @connections.push connection
      connection.on 'end', =>
        @connections.splice @connections.indexOf connection, 1

    @expressServer.get '/', (request, response) =>
      response.send 200, 'hello'

    @engineServer.on 'connection', (connection) =>
      id = uuid.v1()
      @engineConnections[id] = connection
      connection.on 'message', (message) =>
        @ceOperationHub.send id + ':' + message

    @ceOperationHub.on 'message', (buffer) =>
      data = buffer.toString()
      separator = data.indexOf ':'
      id = data.substring 0, separator
      message = data.substring separator + 1
      @engineConnections[id].send message

  stop: (callback) =>
    try
      @connections.forEach (connection) =>
        connection.end()
      @httpServer.close =>
        @ceOperationHub.close()
        callback()
    catch error
      callback error

  start: (callback) =>
    @ceOperationHub.connect @options.ceOperationHub
    @httpServer.listen @options.port, callback
