http = require 'http'
express = require 'express'
zmq = require 'zmq'
uuid = require 'node-uuid'

module.exports = class Server
  constructor: (@options) ->
    @connections = []
    @expressServer = express()
    @httpServer = http.createServer @expressServer
    @ceOperationHub = zmq.socket 'req'

    @httpServer.on 'connection', (connection) =>
      @connections.push connection
      connection.on 'end', =>
        @connections.splice @connections.indexOf connection, 1

    # enable parsing of posted data
    @expressServer.use express.bodyParser()

    @expressServer.get '/', (request, response) =>
      response.send 200, 'hello'

    @expressServer.post '/accounts/:account/orders/', (request, response) =>
      order = request.body
      order.clientRef = uuid.v1()
      order.account = request.params.account
      responseHandler = (message) =>
        orderResponse = JSON.parse message
        if order.clientRef == orderResponse.clientRef
          @ceOperationHub.removeListener 'message', responseHandler
          delete orderResponse.clientRef
          delete orderResponse.account
          response.send 200, orderResponse
      @ceOperationHub.on 'message', responseHandler
      @ceOperationHub.send JSON.stringify order

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
