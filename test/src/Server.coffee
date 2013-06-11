chai = require 'chai'
chai.should()
expect = chai.expect
Checklist = require 'checklist'

Server = require '../../src/Server'

supertest = require 'supertest'
zmq = require 'zmq'
uuid = require 'node-uuid'

describe 'Server', ->
  describe '#stop', ->
    it 'should error if the server has not been started', (done) ->
      server = new Server
        port: 3000
        ceOperationHub: 'tcp://127.0.0.1:8001'
      server.stop (error) ->
        error.message.should.equal 'Not running'
        done()

  describe '#start', ->
    it 'should start and be stoppable', (done) ->
      server = new Server
        port: 8000
        ceOperationHub: 'tcp://127.0.0.1:8001'
      server.start (error) ->
        expect(error).to.not.be.ok
        server.stop (error) ->
          expect(error).to.not.be.ok
          done()

  describe 'when started', ->
    beforeEach (done) ->
      @ceOperationHub = zmq.socket 'xrep'
      @ceOperationHub.bindSync 'tcp://127.0.0.1:8001'
      @server = new Server
        port: 8000
        ceOperationHub: 'tcp://127.0.0.1:8001'
      @server.start done
      @request = supertest 'http://localhost:8000'

    afterEach (done) ->
      @server.stop (error) =>
        @ceOperationHub.close()
        done error

    it 'should return the home page from /', (done) ->
      @request
      .get('/')
      .set('Accept', 'text/html')
      .expect(200)
      .expect('Content-Type', /html/)
      .expect 'hello', done

    it 'should accept deposits posted to /deposits/[account]/ and forward them to the ce-operation-hub', (done) ->
      id = uuid.v1()
      @ceOperationHub.on 'message', =>
        args = Array.apply null, arguments
        deposit = JSON.parse args[2]
        deposit.currency.should.equal 'EUR'
        deposit.amount.should.equal '50'
        deposit.account.should.equal 'Peter'
        deposit.id = id
        args[2] = JSON.stringify deposit
        @ceOperationHub.send args
      @request
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

    it 'should accept orders posted to /orders/[account]/ and forward them to the ce-operation-hub', (done) ->
      id = uuid.v1()
      @ceOperationHub.on 'message', =>
        args = Array.apply null, arguments
        order = JSON.parse args[2]
        order.bidCurrency.should.equal 'EUR'
        order.offerCurrency.should.equal 'BTC'
        order.bidPrice.should.equal '100'
        order.bidAmount.should.equal '50'
        order.account.should.equal 'Peter'
        order.id = id
        args[2] = JSON.stringify order
        @ceOperationHub.send args
      @request
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

    it 'should accept multiple orders posted simultaneously to /orders/[account]/ and forward them to the ce-operation-hub', (done) ->
      timeouts = [1000, 500, 0]
      timeoutIndex = 0
      checklist = new Checklist [
        'EURBTC'
        'BTCEUR'
        'USDBTC'
        ], done
      @ceOperationHub.on 'message', (message) =>
        args = Array.apply null, arguments
        order = JSON.parse args[2]
        order.id = order.bidCurrency + order.offerCurrency
        args[2] = JSON.stringify order
        # reply asynchronously and in reverse order
        setTimeout =>
          @ceOperationHub.send args
        , timeouts[timeoutIndex++]
      @request
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
      @request
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
      @request
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
