chai = require 'chai'
chai.should()
expect = chai.expect

Server = require '../../src/Server'

EngineIOClient = require 'engine.io-client'
supertest = require 'supertest'
zmq = require 'zmq'

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

    it 'should listen for engine.io connections on the specified port', (done) ->
      socket = EngineIOClient 'ws://localhost:8000'
      socket.on 'open', ->
        done()

    it 'should listen for HTTP connections on the specified port', (done) ->
      @request
      .get('/')
      .expect(200)
      .expect 'hello', done

    it 'should forward messages from the engine.io interface to the configured ce-operation-hub 0MQ socket', (done) ->
      @ceOperationHub.on 'message', (message) =>
        @ceOperationHub.send message + ', yourself'
      socket = EngineIOClient 'ws://localhost:8000'
      socket.on 'open', ->
        socket.send 'hello'
      socket.on 'message', (message) ->
        message.should.equal 'hello, yourself'
        done()



