chai = require 'chai'
chai.should()
expect = chai.expect

ChildDaemon = require 'child-daemon'
EngineIOClient = require 'engine.io-client'

describe 'ce-front-end', ->
  it 'should start and listen for engine.io connections', (done) ->
    childDaemon = new ChildDaemon 'node', ['lib/src/index.js'], new RegExp 'ce-front-end started'
    childDaemon.start (error, matched) ->
      expect(error).to.not.be.ok
      socket = EngineIOClient 'ws://localhost:3000'
      socket.on 'open', ->        
        childDaemon.stop (error) ->
          expect(error).to.not.be.ok
          done()
