http = require 'http'
express = require 'express'
zmq = require 'zmq'
uuid = require 'node-uuid'

State = require('currency-market').State
Delta = require('currency-market').Delta
Operation = require('currency-market').Operation
Amount = require('currency-market').Amount

module.exports = class Server
  constructor: (@options) ->
    @connections = []
    @expressServer = express()
    @httpServer = http.createServer @expressServer
    @ceOperationHub = zmq.socket 'dealer'
    @ceDeltaHub =
      stream: zmq.socket 'sub'
      state: zmq.socket 'dealer'
    @ceDeltaHub.stream.subscribe ''
    @deltas = []

    @ceDeltaHub.stream.on 'message', (message) =>
      delta = new Delta
        json: message
      if @state
        @state.apply delta
      else
        @deltas.push delta

    @ceDeltaHub.state.on 'message', (message) =>
      firstState = !@state
      @state = new State
        commission: @options.commission
        json: message
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

    # expose the HAL browser
    @expressServer.use '/hal', express.static 'thirdparty/hal-browser'

    @expressServer.get '/', (request, response) =>
      response.send 200, 'hello'

    @expressServer.get '/balances/:account/', (request, response) =>
      balances = Object.create null
      response.json 200, @state.getAccount(request.params.account).balances

    @expressServer.get '/balances/:account/:currency', (request, response) =>
      response.json 200, @state.getAccount(request.params.account).getBalance(request.params.currency)

    @expressServer.post '/deposits/:account/', (request, response) =>
      reference = uuid.v1()
      responseHandler = (message) =>
        operationResponse = JSON.parse message
        operationResponse.operation = new Operation
          exported: operationResponse.operation
        operationResponse.delta = new Delta
          exported: operationResponse.delta
        if operationResponse.delta.operation.reference == reference
          @ceOperationHub.removeListener 'message', responseHandler
          response.json 200, operationResponse
      @ceOperationHub.on 'message', responseHandler
      operation = new Operation
        reference: reference
        account: request.params.account
        deposit:
          currency: request.body.currency
          amount: new Amount request.body.amount
      @ceOperationHub.send JSON.stringify operation

    @expressServer.post '/orders/:account/', (request, response) =>
      reference = uuid.v1()
      responseHandler = (message) =>
        operationResponse = JSON.parse message
        operationResponse.operation = new Operation
          exported: operationResponse.operation
        operationResponse.delta = new Delta
          exported: operationResponse.delta
        if operationResponse.delta.operation.reference == reference
          @ceOperationHub.removeListener 'message', responseHandler
          response.json 200, operationResponse
      @ceOperationHub.on 'message', responseHandler
      operation = new Operation
        reference: reference
        account: request.params.account
        submit: 
          bidCurrency: request.body.bidCurrency
          offerCurrency: request.body.offerCurrency
          bidPrice: if request.body.bidPrice then new Amount request.body.bidPrice
          bidAmount: if request.body.bidAmount then new Amount request.body.bidAmount
          offerPrice: if request.body.offerPrice then new Amount request.body.offerPrice
          offerAmount: if request.body.offerAmount then new Amount request.body.offerAmount
      @ceOperationHub.send JSON.stringify operation

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
