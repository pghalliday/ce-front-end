chai = require 'chai'
chai.should()
expect = chai.expect

ChildDaemon = require 'child-daemon'
supertest = require 'supertest'
zmq = require 'zmq'

describe 'ce-front-end', ->
  it 'should start and listen for engine.io and HTTP connections', (done) ->
    childDaemon = new ChildDaemon 'node', ['lib/src/index.js'], new RegExp 'ce-front-end started'
    childDaemon.start (error, matched) ->
      expect(error).to.not.be.ok
      supertest('http://localhost:3000')
      .get('/')
      .expect(200)
      .expect 'hello', ->
        childDaemon.stop (error) ->
          expect(error).to.not.be.ok
          done()
