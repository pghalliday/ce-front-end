chai = require 'chai'
chai.should()
expect = chai.expect

ChildDaemon = require 'child-daemon'
supertest = require 'supertest'

describe 'ce-front-end', ->
  describe 'on start', ->
    it 'should take parameters from the command line', (done) ->
      childDaemon = new ChildDaemon 'node', ['lib/src/index.js', '--port', '3001'], new RegExp 'ce-front-end started'
      childDaemon.start (error, matched) ->
        expect(error).to.not.be.ok
        supertest('http://localhost:3001')
        .get('/')
        .expect(200)
        .expect('hello')
        .end (error, response) ->
          expect(error).to.not.be.ok
          childDaemon.stop (error) ->
            expect(error).to.not.be.ok
            done()

    it 'should take parameters from a file', (done) ->
      childDaemon = new ChildDaemon 'node', ['lib/src/index.js', '--config', 'test/support/config.json'], new RegExp 'ce-front-end started'
      childDaemon.start (error, matched) ->
        expect(error).to.not.be.ok
        supertest('http://localhost:3002')
        .get('/')
        .expect(200)
        .expect('hello')
        .end (error, response) ->
          expect(error).to.not.be.ok
          childDaemon.stop (error) ->
            expect(error).to.not.be.ok
            done()

    it 'should override parameters from a file with parameters from the command line', (done) ->
      childDaemon = new ChildDaemon 'node', ['lib/src/index.js', '--config', 'test/support/config.json', '--port', '3003'], new RegExp 'ce-front-end started'
      childDaemon.start (error, matched) ->
        expect(error).to.not.be.ok
        supertest('http://localhost:3003')
        .get('/')
        .expect(200)
        .expect('hello')
        .end (error, response) ->
          expect(error).to.not.be.ok
          childDaemon.stop (error) ->
            expect(error).to.not.be.ok
            done()
