chai = require 'chai'
chai.should()
expect = chai.expect
Checklist = require 'checklist'

Server = require '../../src/Server'

supertest = require 'supertest'
zmq = require 'zmq'
ports = require '../support/ports'
Engine = require('currency-market').Engine
Operation = require('currency-market').Operation
Delta = require('currency-market').Delta
State = require('currency-market').State
Amount = require('currency-market').Amount

request = null
ceOperationHub = null
ceDeltaHub = null
engine = null
state = null
server = null
sequence = 0

COMMISSION_RATE = new Amount '0.001'
COMMISSION_REFERENCE = '0.1%'

applyOperation = (operation) ->
  operation.accept
    sequence: sequence++
    timestamp: Date.now()
  response = 
    operation: operation
  try
    response.delta = engine.apply operation
    state.apply response.delta
    ceDeltaHub.stream.send JSON.stringify response.delta
  catch error
    response.error = error.toString()
  return response

describe 'Server', ->
  beforeEach ->
    httpPort = ports()
    request = supertest 'http://localhost:' + httpPort
    ceOperationHub = zmq.socket 'router'
    ceOperationHubSubmitPort = ports()
    ceOperationHub.bindSync 'tcp://*:' + ceOperationHubSubmitPort
    ceDeltaHub = 
      stream: zmq.socket 'pub'
      state: zmq.socket 'router'
    ceDeltaHubStreamPort = ports()
    ceDeltaHub.stream.bindSync 'tcp://*:' + ceDeltaHubStreamPort
    ceDeltaHubStatePort = ports()
    ceDeltaHub.state.bindSync 'tcp://*:' + ceDeltaHubStatePort
    sequence = 0
    engine = new Engine
      commission:
        account: 'commission'
        calculate: (params) ->
          amount: params.amount.multiply COMMISSION_RATE
          reference: COMMISSION_REFERENCE
    state = new State
      commission:
        account: 'commission'
      json: JSON.stringify engine
    server = new Server
      port: httpPort
      commission:
        account: 'commission'
      'ce-operation-hub':
        host: 'localhost'
        submit: ceOperationHubSubmitPort
      'ce-delta-hub':
        host: 'localhost'
        stream: ceDeltaHubStreamPort
        state: ceDeltaHubStatePort

  afterEach ->
    ceOperationHub.close()
    ceDeltaHub.stream.close()
    ceDeltaHub.state.close()

  describe '#stop', ->
    it 'should error if the server has not been started', (done) ->
      server.stop (error) ->
        error.message.should.equal 'Not running'
        done()

  describe '#start', ->
    it 'should start and be stoppable', (done) ->
      ceDeltaHub.state.on 'message', (ref) =>
        # send the state so that the server can finish starting
        ceDeltaHub.state.send [ref, JSON.stringify state]
      server.start (error) ->
        expect(error).to.not.be.ok
        # request with keep alive to test that the server can stop with open connections
        request
        .get('/')
        .set('Connection', 'Keep-Alive')
        .end (error, response) =>          
          server.stop (error) ->
            expect(error).to.not.be.ok
            done()

  describe 'when started', ->
    beforeEach (done) ->
      checklist = new Checklist [
        'deltas sent'
        'server started'
      ], done
      ceOperationHub.on 'message', (ref, message) =>
        response = applyOperation new Operation
          json: message
        ceOperationHub.send [ref, JSON.stringify response]
      ceDeltaHub.state.on 'message', (ref) =>
        args = Array.apply null, arguments
        # publishing some deltas before sending the state
        applyOperation new Operation
          reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
          account: 'Peter'
          deposit:
            currency: 'EUR'
            amount: new Amount '5000'
        applyOperation new Operation
          reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
          account: 'Peter'
          deposit:
            currency: 'BTC'
            amount: new Amount '50'
        applyOperation new Operation
          reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
          account: 'Paul'
          deposit:
            currency: 'USD'
            amount: new Amount '7500'
        # wait a bit before sending the state to ensure that the previous increases were cached 
        setTimeout =>
          # send the state now which should result in the previous deltas being ignored
          ceDeltaHub.state.send [ref, JSON.stringify state]
          # now send some more deltas
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Peter'
            deposit:
              currency: 'EUR'
              amount: new Amount '2500'
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Peter'
            deposit:
              currency: 'BTC'
              amount: new Amount '75'
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Paul'
            deposit:
              currency: 'USD'
              amount: new Amount '5000'
          # send some deltas for an account not in the sent state
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Tom'
            deposit:
              currency: 'BTC'
              amount: new Amount '2500'
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Tom'
            deposit:
              currency: 'EUR'
              amount: new Amount '2500'
          # wait a bit so that the state has been received then send some more deltas
          setTimeout =>
            applyOperation new Operation
              reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
              account: 'Peter'
              deposit:
                currency: 'BTC'
                amount: new Amount '75'
            applyOperation new Operation
              reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
              account: 'Paul'
              deposit:
                currency: 'USD'
                amount: new Amount '5000'
            applyOperation new Operation
              reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
              account: 'Tom'
              deposit:
                currency: 'BTC'
                amount: new Amount '2500'
            checklist.check 'deltas sent'
          , 250
        , 250
      # send some deltas before the server starts
      applyOperation new Operation
        reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
        account: 'Peter'
        deposit:
          currency: 'EUR'
          amount: new Amount '2500'
      applyOperation new Operation
        reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
        account: 'Peter'
        deposit:
          currency: 'BTC'
          amount: new Amount '25'
      applyOperation new Operation
        reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
        account: 'Peter'
        deposit:
          currency: 'USD'
          amount: new Amount '2500'
      server.start (error) =>
        checklist.check 'server started'

    afterEach (done) ->
      server.stop (error) =>
        done error

    describe 'GET /hal/browser.html', ->
      it 'should serve the HAL browser', (done) ->
        request
        .get('/hal/browser.html')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect /The HAL Browser/, done

    describe 'GET /', ->
      it 'should return the root of the hypermedia API', (done) ->
        request
        .get('/')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:accounts'].href.should.equal '/accounts'
          halResponse._links['ce:books'].href.should.equal '/books'
          done()

    describe 'GET /rels/accounts', ->
      it 'should return the accounts relationship documentation', (done) ->
        request
        .get('/rels/accounts')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/accounts/)
        .expect(/GET/)
        .expect /Fetch a list of accounts/, done

    describe 'GET /rels/books', ->
      it 'should return the books relationship documentation', (done) ->
        request
        .get('/rels/books')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/books/)
        .expect(/GET/)
        .expect /Fetch a list of collections of books by bid currency/, done

    describe 'GET /accounts', ->
      it 'should return the list of accounts', (done) ->
        checks = for id of state.accounts
          id
        checklist = new Checklist checks, done
        request
        .get('/accounts')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          accounts = halResponse._links['ce:account']
          for account in accounts
            account.href.should.equal '/accounts/' + account.title
            checklist.check account.title

    describe 'GET /accounts/:id', ->
      it 'should return a blank account if no account exists', (done) ->
        request
        .get('/accounts/Unknown')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:balances'].href.should.equal '/accounts/Unknown/balances'
          halResponse._links['ce:deposits'].href.should.equal '/accounts/Unknown/deposits'
          halResponse._links['ce:withdrawals'].href.should.equal '/accounts/Unknown/withdrawals'
          halResponse._links['ce:orders'].href.should.equal '/accounts/Unknown/orders'
          done()

      it 'should return an existing account', (done) ->
        request
        .get('/accounts/Peter')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Peter'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:balances'].href.should.equal '/accounts/Peter/balances'
          halResponse._links['ce:deposits'].href.should.equal '/accounts/Peter/deposits'
          halResponse._links['ce:withdrawals'].href.should.equal '/accounts/Peter/withdrawals'
          halResponse._links['ce:orders'].href.should.equal '/accounts/Peter/orders'
          done()

    describe 'POST /accounts/:id/deposits', ->
      it 'should accept deposits and forward them to the ce-operation-hub', (done) ->
        balance = state.getAccount('Peter').getBalance('EUR')
        expectedFunds = balance.funds.add new Amount '50'
        request
        .post('/accounts/Peter/deposits')
        .set('Accept', 'application/json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balance.funds.compareTo(expectedFunds).should.equal 0
          # TODO: actually we should get the new deposit or some kind of error or something
          delta = new Delta
            exported: response.body
          delta.result.funds.compareTo(expectedFunds).should.equal 0
          # TODO: check the balance?
          # request
          # .get('/accounts/Peter/balances/EUR')
          # .set('Accept', 'application/json')
          # .expect(200)
          # .expect('Content-Type', /json/)
          # .end (error, response) =>
          #   expect(error).to.not.be.ok
          #   response.body.funds.should.equal balance.funds.toString()
          #   done()
          done()

    describe 'GET /accounts/:id/deposits', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/accounts/Unknown/deposits')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/deposits'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:deposit'].should.have.length 0
          done()

      it.skip 'should return the deposits logged for the account', (done) ->
        request
        .post('/accounts/Peter/deposits')
        .set('Accept', 'application/json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .get('/accounts/Peter/deposits')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/Peter/deposits'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse._links['ce:deposit'].should.have.length 10
            done()

    describe 'POST /accounts/:id/withdrawals', ->
      it 'should accept withdrawals and forward them to the ce-operation-hub', (done) ->
        balance = state.getAccount('Peter').getBalance('EUR')
        expectedFunds = balance.funds.subtract new Amount '50'
        request
        .post('/accounts/Peter/withdrawals')
        .set('Accept', 'application/json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balance.funds.compareTo(expectedFunds).should.equal 0
          # TODO: actually we should get the new withdrawal or some kind of error or something
          delta = new Delta
            exported: response.body
          delta.result.funds.compareTo(expectedFunds).should.equal 0
          # TODO: check the balance?
          # request
          # .get('/accounts/Peter/balances/EUR')
          # .set('Accept', 'application/json')
          # .expect(200)
          # .expect('Content-Type', /json/)
          # .end (error, response) =>
          #   expect(error).to.not.be.ok
          #   response.body.funds.should.equal balance.funds.toString()
          #   done()
          done()

    describe 'GET /accounts/:id/withdrawals', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/accounts/Unknown/withdrawals')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/withdrawals'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:withdrawal'].should.have.length 0
          done()

      it.skip 'should return the withdrawals logged for the account', (done) ->
        request
        .post('/accounts/Peter/withdrawals')
        .set('Accept', 'application/json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .get('/accounts/Peter/withdrawals')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/Peter/withdrawals'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse._links['ce:withdrawal'].should.have.length 1
            done()

    describe 'GET /accounts/:id/balances', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/accounts/Unknown/balances')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/balances'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:balance'].should.have.length 0
          done()

      it 'should return the account balances received from the ce-delta-hub', (done) ->
        checks = for id of state.accounts
          id
        checklist = new Checklist checks, done
        # can't use for .. of here as it doesn't play nice with closures
        Object.keys(state.accounts).forEach (id) =>
          account = state.accounts[id]
          request
          .get('/accounts/' + id + '/balances')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/' + id + '/balances'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            if account.balances.length > 0
              checks = []
              for currency of account.balances
                checks.push currency
              balancesChecklist = new Checklist checks, (error) =>
                if error
                  checklist.check error
                else
                  checklist.check id
              balances = halResponse._links['ce:balance']
              for balance in balances
                balance.href.should.equal '/accounts/' + id + '/balances/' + balance.title
                balancesChecklist.check balance.title
            else
              checklist.check id

    describe 'GET /accounts/:id/balances/:currency', ->
      it 'should return 0 funds and locked funds for uninitialised balances', (done) ->
        request
        .get('/accounts/Unknown/balances/EUR')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/balances/EUR'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse.funds.should.equal '0'
          halResponse.lockedFunds.should.equal '0'
          done()

      it 'should return the account balance received from the ce-delta-hub', (done) ->
        checks = []
        for id, account of state.accounts
          for currency of account.balances
            checks.push id + currency
        checklist = new Checklist checks, done
        # can't use for .. in here as it doesn't play nice with closures
        Object.keys(state.accounts).forEach (id) =>
          account = state.accounts[id]
          Object.keys(account.balances).forEach (currency) =>
            expectedFunds = account.balances[currency].funds.toString()
            expectedLockedFunds = account.balances[currency].lockedFunds.toString()
            request
            .get('/accounts/' + id + '/balances/' + currency)
            .set('Accept', 'application/hal+json')
            .expect(200)
            .expect('Content-Type', /hal\+json/)
            .end (error, response) =>
              expect(error).to.not.be.ok
              halResponse = JSON.parse response.text
              halResponse._links.self.href.should.equal '/accounts/' + id + '/balances/' + currency
              halResponse._links.curie.name.should.equal 'ce'
              halResponse._links.curie.href.should.equal '/rels/{rel}'
              halResponse._links.curie.templated.should.be.true
              halResponse.funds.should.equal expectedFunds
              halResponse.lockedFunds.should.equal expectedLockedFunds
              checklist.check id + currency

    describe 'POST /accounts/:id/orders', ->
      it 'should forward errors reported from the engine', (done) ->
        account = state.getAccount 'Peter'
        balance = account.getBalance 'EUR'
        orders = account.orders
        book = state.getBook
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'GBP'
          bidPrice: '100'
          bidAmount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          error = response.body.error
          error.should.equal 'Error: Cannot lock funds that are not available'
          done()

      it 'should accept orders and forward them to the ce-operation-hub', (done) ->
        account = state.getAccount 'Peter'
        balance = account.getBalance 'EUR'
        orders = account.orders
        book = state.getBook
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
          bidPrice: '100'
          bidAmount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          delta = new Delta
            exported: response.body
          balance.lockedFunds.compareTo(new Amount '5000').should.equal 0
          order = orders[delta.operation.sequence]
          order.bidCurrency.should.equal 'BTC'
          order.offerCurrency.should.equal 'EUR'
          order.bidPrice.compareTo(new Amount '100').should.equal 0
          order.bidAmount.compareTo(new Amount '50').should.equal 0
          order.account.should.equal 'Peter'
          book[0].should.equal order
          done()

      it 'should accept multiple orders posted simultaneously and forward them to the ce-operation-hub', (done) ->
        checklist = new Checklist [
          'EURBTC'
          'USDEUR'
          'BTCUSD'
        ], done
        account = state.getAccount 'Peter'
        balanceEUR = account.getBalance 'EUR'
        balanceBTC = account.getBalance 'BTC'
        balanceUSD = account.getBalance 'USD'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balanceBTC.lockedFunds.compareTo(new Amount '50').should.equal 0
          checklist.check 'EURBTC'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'USD'
          offerCurrency: 'EUR'
          bidPrice: '0.5'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balanceEUR.lockedFunds.compareTo(new Amount '2500').should.equal 0
          checklist.check 'USDEUR'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'USD'
          bidPrice: '50'
          bidAmount: '25'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balanceUSD.lockedFunds.compareTo(new Amount '1250').should.equal 0
          checklist.check 'BTCUSD'

    describe 'GET /accounts/:id/orders', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/accounts/Unknown/orders')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/orders'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:order'].should.have.length 0
          done()

      it 'should return the currently active orders for the account', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          request
          .post('/accounts/Peter/orders')
          .set('Accept', 'application/json')
          .send
            bidCurrency: 'USD'
            offerCurrency: 'EUR'
            bidPrice: '0.5'
            bidAmount: '5000'
          .expect(200)
          .expect('Content-Type', /json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            request
            .post('/accounts/Peter/orders')
            .set('Accept', 'application/json')
            .send
              bidCurrency: 'BTC'
              offerCurrency: 'USD'
              bidPrice: '50'
              bidAmount: '25'
            .expect(200)
            .expect('Content-Type', /json/)
            .end (error, response) =>
              expect(error).to.not.be.ok
              request
              .get('/accounts/Peter/orders')
              .set('Accept', 'application/hal+json')
              .expect(200)
              .expect('Content-Type', /hal\+json/)
              .end (error, response) =>
                expect(error).to.not.be.ok
                halResponse = JSON.parse response.text
                halResponse._links.self.href.should.equal '/accounts/Peter/orders'
                halResponse._links.curie.name.should.equal 'ce'
                halResponse._links.curie.href.should.equal '/rels/{rel}'
                halResponse._links.curie.templated.should.be.true
                halResponse._links['ce:order'].should.have.length 3
                for order, index in halResponse._links['ce:order']
                  order.href.should.equal '/accounts/Peter/orders/' + order.title
                  order.title.should.equal '' + (index + 14)
                done()

    describe 'GET /accounts/:id/orders/:sequence', ->
      it 'should return 404 error for unknown orders', (done) ->
        request
        .get('/accounts/Peter/orders/1234165')
        .set('Accept', 'application/hal+json')
        .expect 404, done

      it 'should return the order details', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          delta = new Delta
            exported: response.body
          request
          .get('/accounts/Peter/orders/' + delta.operation.sequence)
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/Peter/orders/' + delta.operation.sequence
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse.sequence.should.equal delta.operation.sequence
            halResponse.timestamp.should.be.a 'number'
            halResponse.account.should.equal 'Peter'
            halResponse.bidCurrency.should.equal 'EUR'
            halResponse.offerCurrency.should.equal 'BTC'
            halResponse.bidPrice.should.equal '0.01'
            halResponse.bidAmount.should.equal '5000'
            done()

    describe 'DELETE /accounts/:id/orders/:sequence', ->
      it 'should send a cancel operation to the operation hub and return the engine error if the order does not exist', (done) ->
        request
        .del('/accounts/Peter/orders/1234165')
        .set('Accept', 'application/json')
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          response.body.error.should.equal 'Error: Order cannot be found'
          done()

      it 'should send a cancel operation to the operation hub', (done) ->
        account = state.getAccount 'Peter'
        balance = account.getBalance 'EUR'
        orders = account.orders
        book = state.getBook
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
          bidPrice: '100'
          bidAmount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          delta = new Delta
            exported: response.body
          request
          .del('/accounts/Peter/orders/' + delta.operation.sequence)
          .set('Accept', 'application/json')
          .expect(200)
          .expect('Content-Type', /json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            delta = new Delta
              exported: response.body
            balance.lockedFunds.compareTo(Amount.ZERO).should.equal 0
            expect(orders[delta.operation.cancel.sequence]).to.not.be.ok
            expect(book[0]).to.not.be.ok
            delta.result.lockedFunds.compareTo(Amount.ZERO).should.equal 0
            done()

    describe 'GET /books', ->
      it 'should return an empty list if no books exist', (done) ->
        request
        .get('/books')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/books'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:books-by-bid-currency'].should.have.length 0
          done()

      it 'should return the list of collections of books by bid currency', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .post('/accounts/Peter/orders')
          .set('Accept', 'application/json')
          .send
            bidCurrency: 'USD'
            offerCurrency: 'EUR'
            bidPrice: '0.5'
            bidAmount: '5000'
          .expect(200)
          .expect('Content-Type', /json/)
          .end (error, response) =>
            request
            .post('/accounts/Peter/orders')
            .set('Accept', 'application/json')
            .send
              bidCurrency: 'BTC'
              offerCurrency: 'USD'
              bidPrice: '50'
              bidAmount: '25'
            .expect(200)
            .expect('Content-Type', /json/)
            .end (error, response) =>
              checks = for currency of state.books
                currency
              checks.should.have.length 3
              checklist = new Checklist checks, done
              request
              .get('/books')
              .set('Accept', 'application/hal+json')
              .expect(200)
              .expect('Content-Type', /hal\+json/)
              .end (error, response) =>
                expect(error).to.not.be.ok
                halResponse = JSON.parse response.text
                halResponse._links.self.href.should.equal '/books'
                halResponse._links.curie.name.should.equal 'ce'
                halResponse._links.curie.href.should.equal '/rels/{rel}'
                halResponse._links.curie.templated.should.be.true
                booksByBidCurrency = halResponse._links['ce:books-by-bid-currency']
                for books in booksByBidCurrency
                  books.href.should.equal '/books/' + books.title
                  checklist.check books.title

    describe 'GET /books/:bidCurrency', ->
      it 'should return an empty list if no books exist', (done) ->
        request
        .get('/books/EUR')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/books/EUR'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:book'].should.have.length 0
          done()

      it 'should return the list of collections of books by bid currency', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'GBP'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .post('/accounts/Peter/orders')
          .set('Accept', 'application/json')
          .send
            bidCurrency: 'GBP'
            offerCurrency: 'EUR'
            bidPrice: '0.5'
            bidAmount: '5000'
          .expect(200)
          .expect('Content-Type', /json/)
          .end (error, response) =>
            request
            .post('/accounts/Peter/orders')
            .set('Accept', 'application/json')
            .send
              bidCurrency: 'GBP'
              offerCurrency: 'USD'
              bidPrice: '50'
              bidAmount: '25'
            .expect(200)
            .expect('Content-Type', /json/)
            .end (error, response) =>
              books = state.getBooks 'GBP'
              checks = for currency of books
                currency
              checks.should.have.length 3
              checklist = new Checklist checks, done
              request
              .get('/books/GBP')
              .set('Accept', 'application/hal+json')
              .expect(200)
              .expect('Content-Type', /hal\+json/)
              .end (error, response) =>
                expect(error).to.not.be.ok
                halResponse = JSON.parse response.text
                halResponse._links.self.href.should.equal '/books/GBP'
                halResponse._links.curie.name.should.equal 'ce'
                halResponse._links.curie.href.should.equal '/rels/{rel}'
                halResponse._links.curie.templated.should.be.true
                booksByOfferCurrency = halResponse._links['ce:book']
                for books in booksByOfferCurrency
                  books.href.should.equal '/books/GBP/' + books.title
                  checklist.check books.title

    describe 'POST /books/:bidCurrency/:offerCurrency', ->
      it 'should accept orders and forward them to the ce-operation-hub', (done) ->
        account = state.getAccount 'Peter'
        balance = account.getBalance 'EUR'
        orders = account.orders
        book = state.getBook
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
        request
        .post('/books/BTC/EUR')
        .set('Accept', 'application/json')
        .send
          account: 'Peter'
          bidPrice: '100'
          bidAmount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          delta = new Delta
            exported: response.body
          balance.lockedFunds.compareTo(new Amount '5000').should.equal 0
          order = orders[delta.operation.sequence]
          order.bidCurrency.should.equal 'BTC'
          order.offerCurrency.should.equal 'EUR'
          order.bidPrice.compareTo(new Amount '100').should.equal 0
          order.bidAmount.compareTo(new Amount '50').should.equal 0
          order.account.should.equal 'Peter'
          book[0].should.equal order
          done()

    describe 'GET /books/:bidCurrency/:offerCurrency', ->
      it 'should return an empty list of orders for an unknown book', (done) ->
        request
        .get('/books/Unknown/Unknown')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/books/Unknown/Unknown'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:order-by-book'].should.have.length 0
          done()

      it 'should return a list of orders for a book', (done) ->
        request
        .post('/books/BTC/EUR')
        .set('Accept', 'application/json')
        .send
          account: 'Peter'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .post('/books/BTC/EUR')
          .set('Accept', 'application/json')
          .send
            account: 'Tom'
            offerPrice: '0.01'
            offerAmount: '2500'
          .expect(200)
          .expect('Content-Type', /json/)
          .end (error, response) =>
            request
            .get('/books/BTC/EUR')
            .set('Accept', 'application/hal+json')
            .expect(200)
            .expect('Content-Type', /hal\+json/)
            .end (error, response) =>
              expect(error).to.not.be.ok
              halResponse = JSON.parse response.text
              halResponse._links.self.href.should.equal '/books/BTC/EUR'
              halResponse._links.curie.name.should.equal 'ce'
              halResponse._links.curie.href.should.equal '/rels/{rel}'
              halResponse._links.curie.templated.should.be.true
              halResponse._links['ce:order-by-book'].should.have.length 2
              for order, index in halResponse._links['ce:order-by-book']
                order.href.should.equal '/books/BTC/EUR/' + index
                order.title.should.equal '' + index
              done()

    describe 'GET /books/:bidCurrency/:offerCurrency/:index', ->
      it 'should return 404 error for unknown indices', (done) ->
        request
        .get('/books/BTC/EUR/1234165')
        .set('Accept', 'application/hal+json')
        .expect 404, done

      it 'should return the order details', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          delta = new Delta
            exported: response.body
          request
          .get('/books/EUR/BTC/0')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/books/EUR/BTC/0'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse.sequence.should.equal delta.operation.sequence
            halResponse.timestamp.should.be.a 'number'
            halResponse.account.should.equal 'Peter'
            halResponse.bidCurrency.should.equal 'EUR'
            halResponse.offerCurrency.should.equal 'BTC'
            halResponse.bidPrice.should.equal '0.01'
            halResponse.bidAmount.should.equal '5000'
            done()              
