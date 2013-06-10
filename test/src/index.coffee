chai = require 'chai'
chai.should()
expect = chai.expect

ChildDaemon = require 'child-daemon'
supertest = require 'supertest'
zmq = require 'zmq'
uuid = require 'node-uuid'

describe 'ce-front-end', ->
  describe 'on start', ->
    beforeEach ->
      @id = uuid.v1()
      @ceOperationHub = zmq.socket 'xrep'
      @ceOperationHub.on 'message', =>
        args = Array.apply null, arguments
        order = JSON.parse args[2]
        order.id = @id
        args[2] = JSON.stringify order
        @ceOperationHub.send args

    afterEach ->
      @ceOperationHub.close()

    it 'should take parameters from the command line', (done) ->
      this.timeout 5000
      @ceOperationHub.bindSync 'tcp://127.0.0.1:4001'
      childDaemon = new ChildDaemon 'node', ['lib/src/index.js', '--port', '3001', '--ce-operation-hub', 'tcp://127.0.0.1:4001'], new RegExp 'ce-front-end started'
      childDaemon.start (error, matched) =>
        expect(error).to.not.be.ok
        supertest('http://localhost:3001')
        .post('/accounts/Peter/orders/')
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
          order.id.should.equal @id
          childDaemon.stop (error) =>
            expect(error).to.not.be.ok
            done()

    it 'should take parameters from a file', (done) ->
      this.timeout 5000
      @ceOperationHub.bindSync 'tcp://127.0.0.1:4002'
      childDaemon = new ChildDaemon 'node', ['lib/src/index.js', '--config', 'test/support/testConfig.json'], new RegExp 'ce-front-end started'
      childDaemon.start (error, matched) =>
        expect(error).to.not.be.ok
        supertest('http://localhost:3002')
        .post('/accounts/Peter/orders/')
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
          order.id.should.equal @id
          childDaemon.stop (error) =>
            expect(error).to.not.be.ok
            done()

    it 'should override parameters from a file with parameters from the command line', (done) ->
      this.timeout 5000
      @ceOperationHub.bindSync 'tcp://127.0.0.1:4003'
      childDaemon = new ChildDaemon 'node', ['lib/src/index.js', '--config', 'test/support/testConfig.json', '--port', '3003', '--ce-operation-hub', 'tcp://127.0.0.1:4003'], new RegExp 'ce-front-end started'
      childDaemon.start (error, matched) =>
        expect(error).to.not.be.ok
        supertest('http://localhost:3003')
        .post('/accounts/Peter/orders/')
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
          order.id.should.equal @id
          childDaemon.stop (error) =>
            expect(error).to.not.be.ok
            done()
