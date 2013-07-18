http = require 'http'
express = require 'express'
zmq = require 'zmq'
uuid = require 'node-uuid'
hal = require 'nor-hal'

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
    @expressServer.use '/hal', express.static __dirname + '/../thirdparty/hal-browser'

    @expressServer.get '/', (request, response) =>
      resource = new hal.Resource {}, '/'
      resource.link 'curie', 
        name: 'ce'
        href: '/rels/{rel}'
        templated: true
      resource.link 'ce:accounts', '/accounts'
      response.type 'application/hal+json'
      response.json 200, resource

    @expressServer.get '/accounts', (request, response) =>
      resource = new hal.Resource {}, '/accounts'
      resource.link 'curie', 
        name: 'ce'
        href: '/rels/{rel}'
        templated: true
      for id, account of @state.accounts
        resource.link 'ce:account',
          href: '/accounts/' + id
          title: id
      response.type 'application/hal+json'
      response.json 200, resource

    @expressServer.get '/accounts/:id', (request, response) =>
      resource = new hal.Resource {}, '/accounts/' + request.params.id
      resource.link 'curie', 
        name: 'ce'
        href: '/rels/{rel}'
        templated: true
      resource.link 'ce:balances', '/accounts/' + request.params.id + '/balances'
      resource.link 'ce:deposits', '/accounts/' + request.params.id + '/deposits'
      resource.link 'ce:withdrawals', '/accounts/' + request.params.id + '/withdrawals'
      resource.link 'ce:orders', '/accounts/' + request.params.id + '/orders'
      response.type 'application/hal+json'
      response.json 200, resource

    @expressServer.get '/accounts/:id/balances', (request, response) =>
      balances = @state.getAccount(request.params.id).balances
      resource = new hal.Resource {}, '/accounts/' + request.params.id + '/balances'
      resource.link 'curie', 
        name: 'ce'
        href: '/rels/{rel}'
        templated: true
      links = for currency, balance of balances
        href: '/accounts/' + request.params.id + '/balances/' + currency
        title: currency
      resource.link 'ce:balance', links
      response.type 'application/hal+json'
      response.json 200, resource

    @expressServer.get '/accounts/:id/balances/:currency', (request, response) =>
      balance = @state.getAccount(request.params.id).getBalance request.params.currency
      resource = new hal.Resource balance, '/accounts/' + request.params.id + '/balances/' + request.params.currency
      resource.link 'curie', 
        name: 'ce'
        href: '/rels/{rel}'
        templated: true
      response.type 'application/hal+json'
      response.json 200, resource

    @expressServer.get '/accounts/:id/deposits', (request, response) =>
      resource = new hal.Resource {}, '/accounts/' + request.params.id + '/deposits'
      resource.link 'curie', 
        name: 'ce'
        href: '/rels/{rel}'
        templated: true
      # TODO: return logged deposits
      resource.link 'ce:deposit', []
      response.type 'application/hal+json'
      response.json 200, resource

    @expressServer.post '/accounts/:id/deposits', (request, response) =>
      @sendOperation response, new Operation
        account: request.params.id
        deposit:
          currency: request.body.currency
          amount: new Amount request.body.amount

    @expressServer.get '/accounts/:id/withdrawals', (request, response) =>
      resource = new hal.Resource {}, '/accounts/' + request.params.id + '/withdrawals'
      resource.link 'curie', 
        name: 'ce'
        href: '/rels/{rel}'
        templated: true
      # TODO: return logged withdrawals
      resource.link 'ce:withdrawal', []
      response.type 'application/hal+json'
      response.json 200, resource

    @expressServer.post '/accounts/:id/withdrawals', (request, response) =>
      @sendOperation response, new Operation
        account: request.params.id
        withdraw:
          currency: request.body.currency
          amount: new Amount request.body.amount

    @expressServer.get '/accounts/:id/orders', (request, response) =>
      resource = new hal.Resource {}, '/accounts/' + request.params.id + '/orders'
      resource.link 'curie', 
        name: 'ce'
        href: '/rels/{rel}'
        templated: true
      # TODO: return active orders
      resource.link 'ce:order', []
      response.type 'application/hal+json'
      response.json 200, resource

    @expressServer.post '/accounts/:id/orders', (request, response) =>
      @sendOperation response, new Operation
        account: request.params.id
        submit: 
          bidCurrency: request.body.bidCurrency
          offerCurrency: request.body.offerCurrency
          bidPrice: if request.body.bidPrice then new Amount request.body.bidPrice
          bidAmount: if request.body.bidAmount then new Amount request.body.bidAmount
          offerPrice: if request.body.offerPrice then new Amount request.body.offerPrice
          offerAmount: if request.body.offerAmount then new Amount request.body.offerAmount

  sendOperation: (response, operation) =>
    reference = uuid.v1()
    responseHandler = (message) =>
      parsed = JSON.parse message
      operation = parsed.operation
      if operation && operation.reference == reference
        @ceOperationHub.removeListener 'message', responseHandler
        response.json 200, parsed
    @ceOperationHub.on 'message', responseHandler
    operation.reference = reference
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
