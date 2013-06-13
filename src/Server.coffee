http = require 'http'
express = require 'express'
zmq = require 'zmq'
uuid = require 'node-uuid'

State = require './State'

module.exports = class Server
  constructor: (@options) ->
    @connections = []
    @expressServer = express()
    @httpServer = http.createServer @expressServer
    @ceOperationHub = zmq.socket 'xreq'
    @ceDeltaHubSubscriber = zmq.socket 'sub'
    @ceDeltaHubSubscriber.subscribe ''
    @ceDeltaHubXRequest = zmq.socket 'xreq'
    @increases = []

    @ceDeltaHubSubscriber.on 'message', (message) =>
      increase = JSON.parse message
      if @state
        @state.increaseBalance increase
      else
        @increases.push increase

    @ceDeltaHubXRequest.on 'message', (message) =>
      firstState = !@state
      @state = new State JSON.parse message
      @increases.forEach (increase) =>
        @state.increaseBalance increase
      if firstState
        @httpServer.listen @options.port, @startCallback

    @httpServer.on 'connection', (connection) =>
      @connections.push connection
      connection.on 'end', =>
        @connections.splice @connections.indexOf connection, 1

    # enable parsing of posted data
    @expressServer.use express.bodyParser()

    @expressServer.get '/', (request, response) =>
      response.send 200, 'hello'

    @expressServer.get '/balances/:account/', (request, response) =>
      balances = Object.create null
      for currency, balance of @state.getAccount(request.params.account).balances
        balances[currency] = balance.amount.toString()
      response.json 200, balances

    @expressServer.get '/balances/:account/:currency', (request, response) =>
      response.json 200, @state.getAccount(request.params.account).getBalance(request.params.currency).getAmount()

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
          response.json 200, order
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
          response.json 200, deposit
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
    @startCallback = callback
    @ceOperationHub.connect 'tcp://' + @options.ceOperationHub.host + ':' + @options.ceOperationHub.port
    @ceDeltaHubSubscriber.connect 'tcp://' + @options.ceDeltaHub.host + ':' + @options.ceDeltaHub.subscriberPort
    @ceDeltaHubXRequest.connect 'tcp://' + @options.ceDeltaHub.host + ':' + @options.ceDeltaHub.xRequestPort
    @ceDeltaHubXRequest.send ''
