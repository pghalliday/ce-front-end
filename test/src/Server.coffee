chai = require 'chai'
chai.should()
expect = chai.expect
Checklist = require 'checklist'

Server = require '../../src/Server'

supertest = require 'supertest'
zmq = require 'zmq'
uuid = require 'node-uuid'
ports = require '../support/ports'
Amount = require '../../src/Amount'

request = null
ceOperationHub = null
ceDeltaHub = null
currentDelta = 0
state = null
server = null

applyOperation = (operation) ->
  account = state.accounts[operation.account]
  if !account
    state.accounts[operation.account] = account = 
      balances: Object.create null
  deposit = operation.deposit
  if deposit
    balances = account.balances
    if !balances[deposit.currency]
      balances[deposit.currency] = Amount.ZERO.toString()
    balances[deposit.currency] = ((new Amount(balances[deposit.currency])).add new Amount(deposit.amount)).toString()
  delta = 
    id: currentDelta++
    operation: operation
  state.nextId = currentDelta
  ceDeltaHub.stream.send JSON.stringify delta  

describe 'Server', ->
  beforeEach ->
    httpPort = ports()
    request = supertest 'http://localhost:' + httpPort
    ceOperationHub = zmq.socket 'xrep'
    ceOperationHubSubmitPort = ports()
    ceOperationHub.bindSync 'tcp://*:' + ceOperationHubSubmitPort
    ceDeltaHub = 
      stream: zmq.socket 'pub'
      state: zmq.socket 'xrep'
    ceDeltaHubStreamPort = ports()
    ceDeltaHub.stream.bindSync 'tcp://*:' + ceDeltaHubStreamPort
    ceDeltaHubStatePort = ports()
    ceDeltaHub.state.bindSync 'tcp://*:' + ceDeltaHubStatePort
    currentDelta = 0
    state = 
      accounts: Object.create null
    server = new Server
      port: httpPort
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
      ceDeltaHub.state.on 'message', (ref) =>
        args = Array.apply null, arguments
        # publishing some deltas before sending the state
        applyOperation
          account: 'Peter'
          id: 13
          result: 'success'
          deposit:
            currency: 'EUR'
            amount: '5000'
        applyOperation
          account: 'Peter'
          id: 14
          result: 'success'
          deposit:
            currency: 'BTC'
            amount: '50'
        applyOperation
          account: 'Paul'
          id: 15
          result: 'success'
          deposit:
            currency: 'USD'
            amount: '7500'
        # wait a bit before sending the state to ensure that the previous increases were cached 
        setTimeout =>
          # send the state now which should result in the previous deltas being ignored
          ceDeltaHub.state.send [ref, JSON.stringify state]
          # now send some more deltas
          applyOperation
            account: 'Peter'
            id: 16
            result: 'success'
            deposit:
              currency: 'EUR'
              amount: '2500'
          applyOperation
            account: 'Peter'
            id: 17
            result: 'success'
            deposit:
              currency: 'BTC'
              amount: '75'
          applyOperation
            account: 'Paul'
            id: 18
            result: 'success'
            deposit:
              currency: 'USD'
              amount: '5000'
          # send some deltas for an account not in the sent state
          applyOperation
            account: 'Tom'
            id: 19
            result: 'success'
            deposit:
              currency: 'BTC'
              amount: '2500'
          applyOperation
            account: 'Tom'
            id: 20
            result: 'success'
            deposit:
              currency: 'EUR'
              amount: '2500'
          # wait a bit so that the state has been received then send some more deltas
          setTimeout =>
            applyOperation
              account: 'Peter'
              id: 21
              result: 'success'
              deposit:
                currency: 'BTC'
                amount: '75'
            applyOperation
              account: 'Paul'
              id: 22
              result: 'success'
              deposit:
                currency: 'USD'
                amount: '5000'
            applyOperation
              account: 'Tom'
              id: 23
              result: 'success'
              deposit:
                currency: 'BTC'
                amount: '2500'
            checklist.check 'deltas sent'
          , 250
        , 250
      # send some deltas before the server starts
      applyOperation
        account: 'Peter'
        id: 10
        result: 'success'
        deposit:
          currency: 'EUR'
          amount: '2500'
      applyOperation
        account: 'Peter'
        id: 11
        result: 'success'
        deposit:
          currency: 'BTC'
          amount: '25'
      applyOperation
        account: 'Paul'
        id: 12
        result: 'success'
        deposit:
          currency: 'USD'
          amount: '2500'
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
            for currency, amount of balances
              amount.should.equal account.balances[currency]
            for currency, amount of account.balances
              amount.should.equal balances[currency]
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
          balance.should.equal '0'
          done()

      it 'should return the account balances received from the ce-delta-hub', (done) ->
        checks = []
        for id, account of state.accounts
          for currency of account.balances
            checks.push id + currency
        checklist = new Checklist checks, done
        # can't use for .. in here as it doesn't play nice with closures
        Object.keys(state.accounts).forEach (id) =>
          account = state.accounts[id]
          Object.keys(account.balances).forEach (currency) =>
            expectedBalance = account.balances[currency]
            request
            .get('/balances/' + id + '/' + currency)
            .set('Accept', 'application/json')
            .expect(200)
            .expect('Content-Type', /json/)
            .end (error, response) =>
              expect(error).to.not.be.ok
              balance = response.body
              balance.should.equal expectedBalance
              checklist.check id + currency

    describe 'POST /deposits/[account]/', ->
      it 'should accept deposits and forward them to the ce-operation-hub', (done) ->
        id = uuid.v1()
        ceOperationHub.on 'message', (ref, message) =>
          operation = JSON.parse message
          operation.account.should.equal 'Peter'
          deposit = operation.deposit
          deposit.currency.should.equal 'EUR'
          deposit.amount.should.equal '50'
          operation.id = id
          ceOperationHub.send [ref, JSON.stringify operation]
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
          operation = response.body
          operation.id.should.equal id
          operation.account.should.equal 'Peter'
          deposit = operation.deposit
          deposit.currency.should.equal 'EUR'
          deposit.amount.should.equal '50'
          done()

    describe 'POST /orders/[account]/', ->
      it 'should accept orders and forward them to the ce-operation-hub', (done) ->
        id = uuid.v1()
        ceOperationHub.on 'message', (ref, message) =>
          operation = JSON.parse message
          operation.account.should.equal 'Peter'
          submit = operation.submit
          submit.bidCurrency.should.equal 'EUR'
          submit.offerCurrency.should.equal 'BTC'
          submit.bidPrice.should.equal '100'
          submit.bidAmount.should.equal '50'
          operation.id = id
          ceOperationHub.send [ref, JSON.stringify operation]
        request
        .post('/orders/Peter/')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '100'
          bidAmount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          operation = response.body
          operation.id.should.equal id
          operation.account.should.equal 'Peter'
          submit = operation.submit
          submit.bidCurrency.should.equal 'EUR'
          submit.offerCurrency.should.equal 'BTC'
          submit.bidPrice.should.equal '100'
          submit.bidAmount.should.equal '50'
          done()

      it 'should accept multiple orders posted simultaneously and forward them to the ce-operation-hub', (done) ->
        timeouts = [1000, 500, 0]
        timeoutIndex = 0
        checklist = new Checklist [
          'EURBTC'
          'BTCEUR'
          'USDBTC'
        ], done
        ceOperationHub.on 'message', (ref, message) =>
          operation = JSON.parse message
          operation.id = operation.submit.bidCurrency + operation.submit.offerCurrency
          # reply asynchronously and in reverse order
          setTimeout =>
            ceOperationHub.send [ref, JSON.stringify operation]
          , timeouts[timeoutIndex++]
        request
        .post('/orders/Peter/')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '100'
          bidAmount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          operation = response.body
          operation.id.should.equal 'EURBTC'
          operation.account.should.equal 'Peter'
          submit = operation.submit
          submit.bidCurrency.should.equal 'EUR'
          submit.offerCurrency.should.equal 'BTC'
          submit.bidPrice.should.equal '100'
          submit.bidAmount.should.equal '50'
          checklist.check operation.id
        request
        .post('/orders/Peter/')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          operation = response.body
          operation.id.should.equal 'BTCEUR'
          operation.account.should.equal 'Peter'
          submit = operation.submit
          submit.bidCurrency.should.equal 'BTC'
          submit.offerCurrency.should.equal 'EUR'
          submit.bidPrice.should.equal '0.01'
          submit.bidAmount.should.equal '5000'
          checklist.check operation.id
        request
        .post('/orders/Peter/')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'USD'
          offerCurrency: 'BTC'
          bidPrice: '150'
          bidAmount: '75'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          operation = response.body
          operation.id.should.equal 'USDBTC'
          operation.account.should.equal 'Peter'
          submit = operation.submit
          submit.bidCurrency.should.equal 'USD'
          submit.offerCurrency.should.equal 'BTC'
          submit.bidPrice.should.equal '150'
          submit.bidAmount.should.equal '75'
          checklist.check operation.id
