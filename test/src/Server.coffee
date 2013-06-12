chai = require 'chai'
chai.should()
expect = chai.expect
Checklist = require 'checklist'

Server = require '../../src/Server'

supertest = require 'supertest'
zmq = require 'zmq'
uuid = require 'node-uuid'

request = supertest 'http://localhost:8000'
ceOperationHub = null
ceDeltaHubPublisher = null
ceDeltaHubXReply = null
currentDelta = 0
state = null
server = null

increaseBalance = (increase) ->
  account = state.accounts[increase.account]
  if !account
    state.accounts[increase.account] = account = 
      balances: Object.create null
  balances = account.balances
  if !balances[increase.currency]
    balances[increase.currency] = '0'
  balances[increase.currency] = (parseFloat(balances[increase.currency]) + parseFloat(increase.amount)) + ''
  increase.id = currentDelta++
  state.nextId = currentDelta
  ceDeltaHubPublisher.send JSON.stringify increase  

describe 'Server', ->
  beforeEach ->
    ceOperationHub = zmq.socket 'xrep'
    ceOperationHub.bindSync 'tcp://*:8001'
    ceDeltaHubPublisher = zmq.socket 'pub'
    ceDeltaHubPublisher.bindSync 'tcp://*:8002'
    ceDeltaHubXReply = zmq.socket 'xrep'
    ceDeltaHubXReply.bindSync 'tcp://*:8003'
    currentDelta = 0
    state = 
      accounts: Object.create null
    server = new Server
      port: 8000
      ceOperationHub:
        host: 'localhost'
        port: 8001
      ceDeltaHub:
        host: 'localhost'
        subscriberPort: 8002
        xRequestPort: 8003

  afterEach ->
    ceOperationHub.close()
    ceDeltaHubPublisher.close()
    ceDeltaHubXReply.close()

  describe '#stop', ->
    it 'should error if the server has not been started', (done) ->
      server.stop (error) ->
        error.message.should.equal 'Not running'
        done()

  describe '#start', ->
    it 'should start and be stoppable', (done) ->
      ceDeltaHubXReply.on 'message', =>
        args = Array.apply null, arguments
        # send the state so that the server can finish starting
        args[1] = JSON.stringify state
        ceDeltaHubXReply.send args
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
      ceDeltaHubXReply.on 'message', =>
        args = Array.apply null, arguments
        # publishing some deltas before sending the state
        increaseBalance
          account: 'Peter'
          currency: 'EUR'
          amount: '5000'
        increaseBalance
          account: 'Peter'
          currency: 'BTC'
          amount: '50'
        increaseBalance
          account: 'Paul'
          currency: 'USD'
          amount: '7500'
        # now send the state which should result in the previous deltas being ignored
        args[1] = JSON.stringify state
        ceDeltaHubXReply.send args
        # now send some more deltas
        increaseBalance
          account: 'Peter'
          currency: 'EUR'
          amount: '2500'
        increaseBalance
          account: 'Peter'
          currency: 'BTC'
          amount: '75'
        increaseBalance
          account: 'Paul'
          currency: 'USD'
          amount: '5000'
        # send some deltas for an account not in the sent state
        increaseBalance
          account: 'Tom'
          currency: 'BTC'
          amount: '2500'
        increaseBalance
          account: 'Tom'
          currency: 'EUR'
          amount: '2500'
        # wait a bit so that the state has been received then send some more deltas
        setTimeout =>
          increaseBalance
            account: 'Peter'
            currency: 'BTC'
            amount: '75'
          increaseBalance
            account: 'Paul'
            currency: 'USD'
            amount: '5000'
          increaseBalance
            account: 'Tom'
            currency: 'BTC'
            amount: '2500'
        , 250
        checklist.check 'deltas sent'
      # send some deltas before the server starts
      increaseBalance
        account: 'Peter'
        currency: 'EUR'
        amount: '2500'
      increaseBalance
        account: 'Peter'
        currency: 'BTC'
        amount: '25'
      increaseBalance
        account: 'Paul'
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
      it 'should return the account balances received from the ce-delta-hub', (done) ->
        checklist = new Checklist [
          'Peter'
          'Paul'
          'Tom'
        ], done
        request
        .get('/balances/Peter/')
        .set('Accept', 'application/json')
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balances = response.body
          for currency, amount of balances
            amount.should.equal state.accounts['Peter'].balances[currency]
          for currency, amount of state.accounts['Peter'].balances
            amount.should.equal balances[currency]
          checklist.check 'Peter'
        request
        .get('/balances/Paul/')
        .set('Accept', 'application/json')
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balances = response.body
          for currency, amount of balances
            amount.should.equal state.accounts['Paul'].balances[currency]
          for currency, amount of state.accounts['Paul'].balances
            amount.should.equal balances[currency]
          checklist.check 'Paul'
        request
        .get('/balances/Tom/')
        .set('Accept', 'application/json')
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balances = response.body
          for currency, amount of balances
            amount.should.equal state.accounts['Tom'].balances[currency]
          for currency, amount of state.accounts['Tom'].balances
            amount.should.equal balances[currency]
          checklist.check 'Tom'

    describe 'POST /deposits/[account]/', ->
      it 'should accept deposits and forward them to the ce-operation-hub', (done) ->
        id = uuid.v1()
        ceOperationHub.on 'message', =>
          args = Array.apply null, arguments
          deposit = JSON.parse args[2]
          deposit.currency.should.equal 'EUR'
          deposit.amount.should.equal '50'
          deposit.account.should.equal 'Peter'
          deposit.id = id
          args[2] = JSON.stringify deposit
          ceOperationHub.send args
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
          deposit = response.body
          deposit.currency.should.equal 'EUR'
          deposit.amount.should.equal '50'
          deposit.id.should.equal id
          done()

    describe 'POST /orders/[account]/', ->
      it 'should accept orders and forward them to the ce-operation-hub', (done) ->
        id = uuid.v1()
        ceOperationHub.on 'message', =>
          args = Array.apply null, arguments
          order = JSON.parse args[2]
          order.bidCurrency.should.equal 'EUR'
          order.offerCurrency.should.equal 'BTC'
          order.bidPrice.should.equal '100'
          order.bidAmount.should.equal '50'
          order.account.should.equal 'Peter'
          order.id = id
          args[2] = JSON.stringify order
          ceOperationHub.send args
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
          order = response.body
          order.bidCurrency.should.equal 'EUR'
          order.offerCurrency.should.equal 'BTC'
          order.bidPrice.should.equal '100'
          order.bidAmount.should.equal '50'
          order.id.should.equal id
          done()

      it 'should accept multiple orders posted simultaneously and forward them to the ce-operation-hub', (done) ->
        timeouts = [1000, 500, 0]
        timeoutIndex = 0
        checklist = new Checklist [
          'EURBTC'
          'BTCEUR'
          'USDBTC'
        ], done
        ceOperationHub.on 'message', (message) =>
          args = Array.apply null, arguments
          order = JSON.parse args[2]
          order.id = order.bidCurrency + order.offerCurrency
          args[2] = JSON.stringify order
          # reply asynchronously and in reverse order
          setTimeout =>
            ceOperationHub.send args
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
          order = response.body
          order.bidCurrency.should.equal 'EUR'
          order.offerCurrency.should.equal 'BTC'
          order.bidPrice.should.equal '100'
          order.bidAmount.should.equal '50'
          order.id.should.equal 'EURBTC'
          checklist.check order.id
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
          order = response.body
          order.bidCurrency.should.equal 'BTC'
          order.offerCurrency.should.equal 'EUR'
          order.bidPrice.should.equal '0.01'
          order.bidAmount.should.equal '5000'
          order.id.should.equal 'BTCEUR'
          checklist.check order.id
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
          order = response.body
          order.bidCurrency.should.equal 'USD'
          order.offerCurrency.should.equal 'BTC'
          order.bidPrice.should.equal '150'
          order.bidAmount.should.equal '75'
          order.id.should.equal 'USDBTC'
          checklist.check order.id
