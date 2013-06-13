chai = require 'chai'
chai.should()

Balance = require '../../src/Balance'

describe 'Balance', ->
  it 'should instantiate with a default amount of 0', ->
    balance = new Balance()
    balance.getAmount().should.equal '0'

  describe '#increase', ->
    it 'should increase the amount by the given amount', ->
      balance = new Balance()
      balance.increase '100'
      balance.getAmount().should.equal '100'
      balance.increase '100'
      balance.getAmount().should.equal '200'

  it 'should instantiate from a known state', ->
    balance = new Balance '5000'
    balance.getAmount().should.equal '5000'
