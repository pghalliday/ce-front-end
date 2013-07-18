chai = require 'chai'
chai.should()
expect = chai.expect

ChildDaemon = require 'child-daemon'
supertest = require 'supertest'
zmq = require 'zmq'
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
    delta: engine.apply operation
  state.apply response.delta
  ceDeltaHub.stream.send JSON.stringify response.delta
  return response

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
    applyOperation new Operation
      reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
      account: 'Peter'
      deposit:
        currency: 'EUR'
        amount: new Amount '5000'
    ceOperationHub.on 'message', (ref, message) =>
      response = applyOperation new Operation
        json: message
      ceOperationHub.send [ref, JSON.stringify response]
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
      .get('/accounts/Peter/balances/EUR')
      .set('Accept', 'application/hal+json')
      .expect(200)
      .expect('Content-Type', /hal\+json/)
      .end (error, response) =>
        expect(error).to.not.be.ok
        halResponse = JSON.parse response.text
        halResponse.funds.should.equal '5000'
        childDaemon.stop (error) =>
          expect(error).to.not.be.ok
          ceOperationHub.close()
          ceDeltaHub.stream.close()
          ceDeltaHub.state.close()
          done()
