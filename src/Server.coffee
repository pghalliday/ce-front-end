http = require 'http'
express = require 'express'
zmq = require 'zmq'
uuid = require 'node-uuid'

module.exports = class Server
  constructor: (@options) ->
    @connections = []
    @expressServer = express()
    @httpServer = http.createServer @expressServer
    @ceOperationHub = zmq.socket 'xreq'

    @httpServer.on 'connection', (connection) =>
      @connections.push connection
      connection.on 'end', =>
        @connections.splice @connections.indexOf connection, 1

    # enable parsing of posted data
    @expressServer.use express.bodyParser()

    @expressServer.get '/', (request, response) =>
      response.send 200, 'hello'

    @expressServer.post '/orders/:account/', (request, response) =>
      order = request.body
      order.account = request.params.account
      clientRef = uuid.v1()
      responseHandler = =>
        args = Array.apply null, arguments
        if args[0].toString() == clientRef
          @ceOperationHub.removeListener 'message', responseHandler
          order = JSON.parse args[1]
          delete order.account
          response.send 200, order
      @ceOperationHub.on 'message', responseHandler
      @ceOperationHub.send [clientRef, JSON.stringify order]

    @expressServer.post '/deposits/:account/', (request, response) =>
      deposit = request.body
      deposit.account = request.params.account
      clientRef = uuid.v1()
      responseHandler = =>
        args = Array.apply null, arguments
        if args[0].toString() == clientRef
          @ceOperationHub.removeListener 'message', responseHandler
          deposit = JSON.parse args[1]
          delete deposit.account
          response.send 200, deposit
      @ceOperationHub.on 'message', responseHandler
      @ceOperationHub.send [clientRef, JSON.stringify deposit]

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
