chai = require 'chai'
chai.should()
expect = chai.expect

Relationship = require '../../src/Relationship'

describe 'Relationship', ->
  it 'should record the relationship name', ->
    relationship = new Relationship
      name: 'my relationship'
    relationship.name.should.equal 'my relationship'

  it 'should throw an error if no name is specified', ->
    expect ->
      relationship = new Relationship()
    .to.throw 'Must specify the relationship name'

  describe '#verb', ->
    it 'should record the name, request example and response example and return the relationship for chaining', ->
      relationship = new Relationship
        name: 'my relationship'
      .verb
        name: 'GET'
        request: 'GET params'
        response: 'GET response'
      .verb
        name: 'POST'
        request: 'POST params'
        response: 'POST response'
      .verb
        name: 'DELETE'
        request: 'DELETE params'
        response: 'DELETE response'
      relationship.verbs['GET'].request.should.equal 'GET params'
      relationship.verbs['GET'].response.should.equal 'GET response'
      relationship.verbs['POST'].request.should.equal 'POST params'
      relationship.verbs['POST'].response.should.equal 'POST response'
      relationship.verbs['DELETE'].request.should.equal 'DELETE params'
      relationship.verbs['DELETE'].response.should.equal 'DELETE response'

    it 'should throw an error if no name is specified', ->
      expect ->
        relationship = new Relationship
          name: 'my relationship'
        .verb
          request: 'GET params'
          response: 'GET response'
      .to.throw 'Must specify the verb name'
