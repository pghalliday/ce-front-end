http = require 'http'
express = require 'express'
zmq = require 'zmq'
uuid = require 'node-uuid'
hal = require 'nor-hal'

State = require('currency-market').State
Delta = require('currency-market').Delta
Operation = require('currency-market').Operation
Amount = require('currency-market').Amount

newHalResource = (object, self) ->
  resource = new hal.Resource object, self
  resource.link 'curie', 
    name: 'ce'
    href: '/rels/{rel}'
    templated: true

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
    @outstanding = {}

    @ceOperationHub.on 'message', (message) =>
      response = JSON.parse message
      if response.error
        operation = response.operation
        if operation
          outstanding = @outstanding[operation.reference]
          if outstanding
            delete @outstanding[operation.reference]
            outstanding.response.json 200, response

    @ceDeltaHub.stream.on 'message', (message) =>
      delta = new Delta
        json: message
      if @state
        @applyDelta delta
      else
        @deltas.push delta

    @ceDeltaHub.state.on 'message', (message) =>
      firstState = !@state
      @state = new State
        commission: @options.commission
        json: message
      @deltas.forEach (delta) =>
        @applyDelta delta
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
      response.type 'application/hal+json'
      response.json 200,
        newHalResource({}, '/')
        .link('ce:accounts', '/accounts')
        .link('ce:books', '/books')

    @expressServer.get '/accounts', (request, response) =>
      response.type 'application/hal+json'
      accounts = for id of @state.accounts
        href: '/accounts/' + id
        title: id
      response.json 200,
        newHalResource({}, '/accounts')
        .link('ce:account', accounts)

    @expressServer.get '/accounts/:id', (request, response) =>
      response.type 'application/hal+json'
      response.json 200,
        newHalResource({}, '/accounts/' + request.params.id)
        .link('ce:balances', '/accounts/' + request.params.id + '/balances')
        .link('ce:deposits', '/accounts/' + request.params.id + '/deposits')
        .link('ce:withdrawals', '/accounts/' + request.params.id + '/withdrawals')
        .link('ce:orders', '/accounts/' + request.params.id + '/orders')

    @expressServer.get '/accounts/:id/balances', (request, response) =>
      response.type 'application/hal+json'
      balances = for currency of @state.getAccount(request.params.id).balances
        href: '/accounts/' + request.params.id + '/balances/' + currency
        title: currency
      response.json 200,
        newHalResource({}, '/accounts/' + request.params.id + '/balances')
        .link('ce:balance', balances)

    @expressServer.get '/accounts/:id/balances/:currency', (request, response) =>
      response.type 'application/hal+json'
      response.json 200,
        newHalResource @state.getAccount(request.params.id).getBalance(request.params.currency), '/accounts/' + request.params.id + '/balances/' + request.params.currency

    @expressServer.post '/accounts/:id/deposits', (request, response) =>
      @sendOperation response, new Operation
        account: request.params.id
        deposit:
          currency: request.body.currency
          amount: new Amount request.body.amount

    @expressServer.get '/accounts/:id/deposits', (request, response) =>
      response.type 'application/hal+json'
      # TODO: return logged deposits
      response.json 200,
        newHalResource({}, '/accounts/' + request.params.id + '/deposits')
        .link('ce:deposit', [])

    @expressServer.post '/accounts/:id/withdrawals', (request, response) =>
      @sendOperation response, new Operation
        account: request.params.id
        withdraw:
          currency: request.body.currency
          amount: new Amount request.body.amount

    @expressServer.get '/accounts/:id/withdrawals', (request, response) =>
      response.type 'application/hal+json'
      # TODO: return logged withdrawals
      response.json 200,
        newHalResource({}, '/accounts/' + request.params.id + '/withdrawals')
        .link('ce:withdrawal', [])

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

    @expressServer.get '/accounts/:id/orders', (request, response) =>
      response.type 'application/hal+json'
      orders = for sequence of @state.getAccount(request.params.id).orders
        href: '/accounts/' + request.params.id + '/orders/' + sequence
        title: sequence
      response.json 200,
        newHalResource({}, '/accounts/' + request.params.id + '/orders')
        .link('ce:order', orders)

    @expressServer.get '/accounts/:id/orders/:sequence', (request, response) =>
      order = @state.getAccount(request.params.id).orders[request.params.sequence]
      if order
        response.type 'application/hal+json'
        response.json 200,
          newHalResource order, '/accounts/' + request.params.id + '/orders/' + request.params.sequence
      else
        response.send 404

    @expressServer.delete '/accounts/:id/orders/:sequence', (request, response) =>
      @sendOperation response, new Operation
        account: request.params.id
        cancel: 
          sequence: parseInt request.params.sequence

    @expressServer.get '/books', (request, response) =>
      response.type 'application/hal+json'
      booksByBidCurrency = for currency of @state.books
        href: '/books/' + currency
        title: currency
      response.json 200,
        newHalResource({}, '/books')
        .link('ce:books-by-bid-currency', booksByBidCurrency)

    @expressServer.get '/books/:bidCurrency', (request, response) =>
      response.type 'application/hal+json'
      booksByOfferCurrency = for currency of @state.getBooks request.params.bidCurrency
        href: '/books/' + request.params.bidCurrency + '/' + currency
        title: currency
      response.json 200,
        newHalResource({}, '/books/' + request.params.bidCurrency)
        .link('ce:book', booksByOfferCurrency)

    @expressServer.post '/books/:bidCurrency/:offerCurrency', (request, response) =>
      @sendOperation response, new Operation
        account: request.body.account
        submit: 
          bidCurrency: request.params.bidCurrency
          offerCurrency: request.params.offerCurrency
          bidPrice: if request.body.bidPrice then new Amount request.body.bidPrice
          bidAmount: if request.body.bidAmount then new Amount request.body.bidAmount
          offerPrice: if request.body.offerPrice then new Amount request.body.offerPrice
          offerAmount: if request.body.offerAmount then new Amount request.body.offerAmount

    @expressServer.get '/books/:bidCurrency/:offerCurrency', (request, response) =>
      response.type 'application/hal+json'
      orders = @state.getBook
        bidCurrency: request.params.bidCurrency
        offerCurrency: request.params.offerCurrency
      orders = for index of orders
        href: '/books/' + request.params.bidCurrency + '/' + request.params.offerCurrency + '/' + index
        title: index
      response.json 200,
        newHalResource({}, '/books/' + request.params.bidCurrency + '/' + request.params.offerCurrency)
        .link('ce:order-by-book', orders)

    @expressServer.get '/books/:bidCurrency/:offerCurrency/:index', (request, response) =>
      orders = @state.getBook
        bidCurrency: request.params.bidCurrency
        offerCurrency: request.params.offerCurrency
      order = orders[request.params.index]
      if order
        response.type 'application/hal+json'
        response.json 200,
          newHalResource order, '/books/' + request.params.bidCurrency + '/' + request.params.offerCurrency + '/' + request.params.index
      else
        response.send 404

  applyDelta: (delta) =>
    @state.apply delta
    operation = delta.operation
    outstanding = @outstanding[operation.reference]
    if outstanding
      delete @outstanding[operation.reference]
      outstanding.response.json 200, delta

  sendOperation: (response, operation) =>
    reference = uuid.v1()
    operation.reference = reference
    @outstanding[reference] = 
      response: response
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
