chai = require 'chai'
chai.should()
expect = chai.expect

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
      @ceOperationHub = zmq.socket 'rep'
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

    it 'should listen for HTTP connections on the specified port', (done) ->
      @request
      .get('/')
      .expect(200)
      .expect 'hello', done

    it 'should accept orders posted to /accounts/[account]/orders/ and forward them to the ce-operation-hub', (done) ->
      id = uuid.v1()
      @ceOperationHub.on 'message', (message) =>
        order = JSON.parse message
        order.bidCurrency.should.equal 'EUR'
        order.orderCurrency.should.equal 'BTC'
        order.bidPrice.should.equal '100'
        order.bidAmount.should.equal '50'
        order.account.should.equal 'Peter'
        order.id = id
        @ceOperationHub.send JSON.stringify order
      @request
      .post('/accounts/Peter/orders/')
      .set('Accept', 'application/json')
      .send
        bidCurrency: 'EUR'
        orderCurrency: 'BTC'
        bidPrice: '100'
        bidAmount: '50'
      .expect(200)
      .expect('Content-Type', /json/)
      .end (error, response) =>
        order = response.body
        order.bidCurrency.should.equal 'EUR'
        order.orderCurrency.should.equal 'BTC'
        order.bidPrice.should.equal '100'
        order.bidAmount.should.equal '50'
        order.id.should.equal id
        done()



