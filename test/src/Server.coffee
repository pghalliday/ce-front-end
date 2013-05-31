chai = require 'chai'
chai.should()
expect = chai.expect

Server = require '../../src/Server'
EngineIOClient = require 'engine.io-client'

describe 'Server', ->
  describe '#stop', ->
    it 'should error if the server has not been started', (done) ->
      server = new Server
        port: 3000
      server.stop (error) ->
        error.message.should.equal 'Not running'
        done()

  describe '#start', ->
    it 'should start and listen for engine.io connections on the specified port', (done) ->
      server = new Server
        port: 8000
      server.start (error) ->    
        expect(error).to.not.be.ok
        socket = EngineIOClient 'ws://localhost:8000'
        socket.on 'open', ->        
          server.stop (error) ->
            expect(error).to.not.be.ok
            done()

