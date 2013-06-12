chai = require 'chai'
chai.should()
expect = chai.expect

ChildDaemon = require 'child-daemon'
supertest = require 'supertest'
zmq = require 'zmq'

request = supertest 'http://localhost:8000'
ceOperationHub = null
ceDeltaHubPublisher = null
ceDeltaHubXReply = null
state = null

describe 'ce-front-end', ->
  describe 'on start', ->
    beforeEach ->
      ceOperationHub = zmq.socket 'xrep'
      ceOperationHub.bindSync 'tcp://*:8001'
      ceDeltaHubPublisher = zmq.socket 'pub'
      ceDeltaHubPublisher.bindSync 'tcp://*:8002'
      ceDeltaHubXReply = zmq.socket 'xrep'
      ceDeltaHubXReply.bindSync 'tcp://*:8003'
      state =
        nextId: 1234567890
        accounts:
          'Peter':
            balances:
              'EUR': '5000'
              'BTC': '50'
      ceDeltaHubXReply.on 'message', =>
        args = Array.apply null, arguments
        # send the state so that the server can finish starting
        args[1] = JSON.stringify state
        ceDeltaHubXReply.send args

    afterEach ->
      ceOperationHub.close()
      ceDeltaHubPublisher.close()
      ceDeltaHubXReply.close()

    it 'should take parameters from a file specified on the command line', (done) ->
      this.timeout 5000
      childDaemon = new ChildDaemon 'node', [
        'lib/src/index.js',
        '--config',
        'test/support/testConfig.json'
      ], new RegExp 'ce-front-end started'
      childDaemon.start (error, matched) =>
        expect(error).to.not.be.ok
        request
        .get('/balances/Peter/')
        .set('Accept', 'application/json')
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balances = response.body
          balances['EUR'].should.equal '5000'
          balances['BTC'].should.equal '50'
          childDaemon.stop (error) =>
            expect(error).to.not.be.ok
            done()
