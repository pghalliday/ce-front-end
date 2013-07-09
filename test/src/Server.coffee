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
  delta = engine.apply operation
  state.apply delta
  ceDeltaHub.stream.send JSON.stringify delta
  return delta

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
        delta = applyOperation new Operation
          json: message
        ceOperationHub.send [ref, JSON.stringify delta]
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


    describe 'GET /', ->
      it 'should return the home page', (done) ->
        request
        .get('/')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect 'hello', done

    describe 'GET /hal/browser.html', ->
      it 'should serve the HAL browser', (done) ->
        request
        .get('/hal/browser.html')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect /The HAL Browser/, done

    describe 'GET /balances/[account]/', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/balances/Unknown/')
        .set('Accept', 'application/json')
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balances = response.body
          balances.should.deep.equal Object.create null
          done()

      it 'should return the account balances received from the ce-delta-hub', (done) ->
        checks = []
        for id of state.accounts
          checks.push id
        checklist = new Checklist checks, done
        # can't use for .. in here as it doesn't play nice with closures
        Object.keys(state.accounts).forEach (id) =>
          account = state.accounts[id]
          request
          .get('/balances/' + id + '/')
          .set('Accept', 'application/json')
          .expect(200)
          .expect('Content-Type', /json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            balances = response.body
            for currency, balance of balances
              balance.funds.should.equal account.balances[currency].funds.toString()
              balance.lockedFunds.should.equal account.balances[currency].lockedFunds.toString()
            for currency, balance of account.balances
              balance.funds.toString().should.equal balances[currency].funds
              balance.lockedFunds.toString().should.equal balances[currency].lockedFunds
            checklist.check id

    describe 'GET /balances/[account]/[currency]', ->
      it 'should return 0 for uninitialised balances', (done) ->
        request
        .get('/balances/Unknown/EUR')
        .set('Accept', 'application/json')
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balance = response.body
          balance.funds.should.equal '0'
          balance.lockedFunds.should.equal '0'
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
            .get('/balances/' + id + '/' + currency)
            .set('Accept', 'application/json')
            .expect(200)
            .expect('Content-Type', /json/)
            .end (error, response) =>
              expect(error).to.not.be.ok
              balance = response.body
              balance.funds.should.equal expectedFunds
              balance.lockedFunds.should.equal expectedLockedFunds
              checklist.check id + currency

    describe 'POST /deposits/[account]/', ->
      it 'should accept deposits and forward them to the ce-operation-hub', (done) ->
        balance = state.getAccount('Peter').getBalance('EUR')
        funds = balance.funds
        request
        .post('/deposits/Peter/')
        .set('Accept', 'application/json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          delta = new Delta
            json: response.text
          balance.funds.compareTo(funds.add(new Amount '50')).should.equal 0
          delta.result.funds.compareTo(balance.funds).should.equal 0
          done()

    describe 'POST /orders/[account]/', ->
      it 'should accept orders and forward them to the ce-operation-hub', (done) ->
        account = state.getAccount 'Peter'
        balance = account.getBalance 'EUR'
        orders = account.orders
        book = state.getBook
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
        request
        .post('/orders/Peter/')
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
            json: response.text
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
        .post('/orders/Peter/')
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
        .post('/orders/Peter/')
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
        .post('/orders/Peter/')
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
