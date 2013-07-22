http = require 'http'
express = require 'express'
zmq = require 'zmq'
uuid = require 'node-uuid'
hal = require 'nor-hal'
path = require 'path'

State = require('currency-market').State
Delta = require('currency-market').Delta
Operation = require('currency-market').Operation
Amount = require('currency-market').Amount

Relationship = require './Relationship'
Verb = require './Relationship/Verb'
Response = require './Relationship/Response'
Link = require './Relationship/Link'
Request = require './Relationship/Request'
Example = require './Relationship/Example'

curies = [
  name: 'ce'
  href: '/rels/{rel}'
  templated: true
]

newHalResource = (object, self) ->
  resource = new hal.Resource object, self
  for curie in curies
    resource.link 'curie', 
      curie
  return resource

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

    # express options
    @expressServer.set 'views', path.join __dirname, '..', 'views'
    @expressServer.set 'view engine', 'jade'
    @expressServer.use express.favicon()
    # TODO: add logging?
    # @expressServer.use express.logger 'dev'
    @expressServer.use express.bodyParser()
    @expressServer.use express.methodOverride()
    @expressServer.use @expressServer.router
    @expressServer.use express.static path.join __dirname, '..', 'public'

    # expose the HAL browser
    @expressServer.use '/hal', express.static path.join __dirname, '..', 'thirdparty/hal-browser'

    @expressServer.get '/', (request, response) =>
      response.type 'application/hal+json'
      response.json 200,
        newHalResource({}, '/')
        .link('ce:accounts', '/accounts')
        .link('ce:books', '/books')

    @expressServer.get '/rels/accounts', (request, response) =>
      relationship = new Relationship
        name: 'ce:accounts'
      .verb new Verb
        name: 'GET'
        description: 'Fetch a list of accounts'
      .response new Response
        name: '200 OK'
      .link(new Link
        curies: curies
        relationship: 'ce:account'
        description: 'an array of account links')
      response.render 'relationship', relationship

    @expressServer.get '/rels/books', (request, response) =>
      relationship = new Relationship
        name: 'ce:books'
      .verb new Verb
        name: 'GET'
        description: 'Fetch a list of collections of books by bid currency'
      .response new Response
        name: '200 OK'
      .link(new Link
        curies: curies
        relationship: 'ce:books-by-bid-currency'
        description: 'an array of links to collections of books by bid currency')
      response.render 'relationship', relationship

    @expressServer.get '/accounts', (request, response) =>
      response.type 'application/hal+json'
      accounts = for id of @state.accounts
        href: '/accounts/' + id
        title: id
      response.json 200,
        newHalResource({}, '/accounts')
        .link('ce:account', accounts)

    @expressServer.get '/rels/account', (request, response) =>
      relationship = new Relationship
        name: 'ce:account'
      .verb new Verb
        name: 'GET'
        description: 'Fetch an account state'
      .response new Response
        name: '200 OK'
      .link(new Link
        curies: curies
        relationship: 'ce:balances'
        description: 'link to the collection of currency balances')
      .link(new Link
        curies: curies
        relationship: 'ce:deposits'
        description: 'link to the collection of logged deposits')
      .link(new Link
        curies: curies
        relationship: 'ce:withdrawals'
        description: 'link to the collection of logged withdrawals')
      .link(new Link
        curies: curies
        relationship: 'ce:orders'
        description: 'link to the collection of active orders')
      response.render 'relationship', relationship

    @expressServer.get '/accounts/:id', (request, response) =>
      response.type 'application/hal+json'
      response.json 200,
        newHalResource({}, '/accounts/' + request.params.id)
        .link('ce:balances', '/accounts/' + request.params.id + '/balances')
        .link('ce:deposits', '/accounts/' + request.params.id + '/deposits')
        .link('ce:withdrawals', '/accounts/' + request.params.id + '/withdrawals')
        .link('ce:orders', '/accounts/' + request.params.id + '/orders')

    @expressServer.get '/rels/balances', (request, response) =>
      relationship = new Relationship
        name: 'ce:balances'
      .verb new Verb
        name: 'GET'
        description: 'Fetch the list of currency balances for the account'
      .response new Response
        name: '200 OK'
      .link(new Link
        curies: curies
        relationship: 'ce:balance'
        description: 'an array of links to balances in each currency')
      response.render 'relationship', relationship

    @expressServer.get '/rels/deposits', (request, response) =>
      relationship = new Relationship
        name: 'ce:deposits'
      .verb(new Verb
        name: 'GET'
        description: 'Fetch the list of logged deposits for the account'
      .response new Response
        name: '200 OK'
      .link(new Link
        curies: curies
        relationship: 'ce:deposit'
        description: 'an array of links to logged deposits'))
      .verb(new Verb
        name: 'POST'
        description: 'Deposit funds into an account'
      .setRequest(new Request()
      .example new Example
        description: 'Deposit 5000 Euros'
        data:
          currency: 'EUR'
          amount: '5000')
      .response(new Response
        name: '200 OK'
      .example(new Example
        description: 'After successfully applying the deposit operation a delta will be received giving the new funds available in the relevent account balance'
        data:
          operation:
            sequence: 123456789
            timestamp: 13789945543
            account: 'AccountId'
            deposit:
              currency: 'EUR'
              amount: '5000'
          result:
            funds: '123456787.454')
      .example(new Example
        description: 'When the deposit operation takes too long a pending flag will be received. The deposit may still succeed at a later time'
        data:
          operation:
            sequence: 123456789
            timestamp: 13789945543
            account: 'AccountId'
            deposit:
              currency: 'EUR'
              amount: '5000'
          pending: true)
      .example(new Example
        description: 'When an error is encountered applying the deposit operation the error message will be received'
        data:
          operation:
            sequence: 123456789
            timestamp: 13789945543
            account: 'AccountId'
            deposit:
              currency: 'EUR'
              amount: '5000'
          error: 'Error: some error')))
      response.render 'relationship', relationship

    @expressServer.get '/rels/withdrawals', (request, response) =>
      relationship = new Relationship
        name: 'ce:withdrawals'
      .verb(new Verb
        name: 'GET'
        description: 'Fetch the list of logged withdrawals for the account'
      .response new Response
        name: '200 OK'
      .link(new Link
        curies: curies
        relationship: 'ce:withdrawal'
        description: 'an array of links to logged withdrawals'))
      .verb(new Verb
        name: 'POST'
        description: 'Withdraw funds from an account'
      .setRequest(new Request()
      .example new Example
        description: 'Withdraw 5000 Euros'
        data:
          currency: 'EUR'
          amount: '5000')
      .response(new Response
        name: '200 OK'
      .example(new Example
        description: 'After successfully applying the withdraw operation a delta will be received giving the new funds available in the relevent account balance'
        data:
          operation:
            sequence: 123456789
            timestamp: 13789945543
            account: 'AccountId'
            withdraw:
              currency: 'EUR'
              amount: '5000'
          result:
            funds: '123456787.454')
      .example(new Example
        description: 'When the withdraw operation takes too long a pending flag will be received. The withdrawal may still succeed at a later time'
        data:
          operation:
            sequence: 123456789
            timestamp: 13789945543
            account: 'AccountId'
            withdraw:
              currency: 'EUR'
              amount: '5000'
          pending: true)
      .example(new Example
        description: 'When an error is encountered applying the withdraw operation the error message will be received'
        data:
          operation:
            sequence: 123456789
            timestamp: 13789945543
            account: 'AccountId'
            withdraw:
              currency: 'EUR'
              amount: '5000'
          error: 'Error: some error')))
      response.render 'relationship', relationship

    @expressServer.get '/rels/orders', (request, response) =>
      relationship = new Relationship
        name: 'ce:orders'
      .verb(new Verb
        name: 'GET'
        description: 'Fetch the list of active orders for the account'
      .response new Response
        name: '200 OK'
      .link(new Link
        curies: curies
        relationship: 'ce:order'
        description: 'an array of links to active orders'))
      .verb(new Verb
        name: 'POST'
        description: 'Submit a new order to the market'
      .setRequest(new Request()
      .example(new Example
        description: 'For bid orders specify the bid price as the amount of the offer currency being bid for 1 unit of the bid currency and a bid amount as the number of units of the bid currency being requested'
        data:
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000')
      .example(new Example
        description: 'For offer orders specify the offer price as the amount of the bid currency required for 1 unit of the offer currency and an offer amount as the number of units of the offer currency being offered'
        data:
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          offerPrice: '100'
          offerAmount: '50')))
      response.render 'relationship', relationship

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
