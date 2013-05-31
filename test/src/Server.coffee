chai = require 'chai'
chai.should()
expect = chai.expect

Server = require '../../src/Server'
EngineIOClient = require 'engine.io-client'
supertest = require 'supertest'

describe 'Server', ->
  describe '#stop', ->
    it 'should error if the server has not been started', (done) ->
      server = new Server
        port: 3000
      server.stop (error) ->
        error.message.should.equal 'Not running'
        done()

  describe '#start', ->
    it 'should start and be stoppable', (done) ->
      server = new Server
        port: 8000
      server.start (error) ->    
        expect(error).to.not.be.ok
        server.stop (error) ->
          expect(error).to.not.be.ok
          done()

  describe 'when started', ->
    beforeEach (done) ->
      @server = new Server
        port: 8000
      @server.start done
      @request = supertest 'http://localhost:8000'

    afterEach (done) ->
      @server.stop done

    it 'should listen for engine.io connections on the specified port', (done) ->
      socket = EngineIOClient 'ws://localhost:8000'
      socket.on 'open', ->
        done()

    it 'should listen for HTTP connections on the specified port', (done) ->
      @request
      .get('/')
      .expect(200)
      .expect 'hello', done


