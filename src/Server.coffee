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
    @ceDeltaHub =
      stream: zmq.socket 'sub'
      state: zmq.socket 'xreq'
    @ceDeltaHub.stream.subscribe ''
    @deltas = []

    @ceDeltaHub.stream.on 'message', (message) =>
      delta = JSON.parse message
      if @state
        @state.apply delta
      else
        @deltas.push delta

    @ceDeltaHub.state.on 'message', (message) =>
      firstState = !@state
      @state = new State JSON.parse message
      @deltas.forEach (delta) =>
        @state.apply delta
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

    @expressServer.post '/deposits/:account/', (request, response) =>
      frontEndRef = uuid.v1()
      responseHandler = (ref, message) =>
        if ref.toString() == frontEndRef
          @ceOperationHub.removeListener 'message', responseHandler
          operation = JSON.parse message
          response.json 200, operation
      @ceOperationHub.on 'message', responseHandler
      operation = 
        account: request.params.account
        deposit: request.body
      @ceOperationHub.send [frontEndRef, JSON.stringify operation]

    @expressServer.post '/orders/:account/', (request, response) =>
      frontEndRef = uuid.v1()
      responseHandler = (ref, message) =>
        if ref.toString() == frontEndRef
          @ceOperationHub.removeListener 'message', responseHandler
          operation = JSON.parse message
          response.json 200, operation
      @ceOperationHub.on 'message', responseHandler
      operation = 
        account: request.params.account
        submit: request.body
      @ceOperationHub.send [frontEndRef, JSON.stringify operation]

  stop: (callback) =>
    try
      @connections.forEach (connection) =>
        connection.end()
      @httpServer.close =>
        @ceOperationHub.close()
        @ceDeltaHub.stream.close()
        @ceDeltaHub.state.close()
        callback()
    catch error
      callback error

  start: (callback) =>
    @startCallback = callback
    @ceOperationHub.connect 'tcp://' + @options['ce-operation-hub'].host + ':' + @options['ce-operation-hub'].submit
    @ceDeltaHub.stream.connect 'tcp://' + @options['ce-delta-hub'].host + ':' + @options['ce-delta-hub'].stream
    @ceDeltaHub.state.connect 'tcp://' + @options['ce-delta-hub'].host + ':' + @options['ce-delta-hub'].state
    @ceDeltaHub.state.send ''
