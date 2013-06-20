chai = require 'chai'
chai.should()
expect = chai.expect

ChildDaemon = require 'child-daemon'
supertest = require 'supertest'
zmq = require 'zmq'

describe 'ce-front-end', ->
  it 'should take parameters from a file specified on the command line', (done) ->
    this.timeout 5000
    request = supertest 'http://localhost:7000'
    ceOperationHub = zmq.socket 'router'
    ceOperationHub.bindSync 'tcp://*:7001'
    ceDeltaHub = 
      stream: zmq.socket 'pub'
      state: zmq.socket 'router'
    ceDeltaHub.stream.bindSync 'tcp://*:7002'
    ceDeltaHub.state.bindSync 'tcp://*:7003'
    state =
      nextSequence: 1234567890
      accounts:
        'Peter':
          balances:
            'EUR': '5000'
            'BTC': '50'
    ceDeltaHub.state.on 'message', (ref) =>
      # send the state so that the server can finish starting
      ceDeltaHub.state.send [ref, JSON.stringify state]
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
          ceOperationHub.close()
          ceDeltaHub.stream.close()
          ceDeltaHub.state.close()
          done()
