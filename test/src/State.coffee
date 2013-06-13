chai = require 'chai'
chai.should()
expect = chai.expect

State = require '../../src/State'
Account = require '../../src/Account'

describe 'State', ->
  describe '#getAccount', ->
    it 'should create a new account if it does not exist', ->
      state = new State()
      account = state.getAccount 'Peter'
      account.should.be.an.instanceOf Account

    it 'should return the corresponding account if it does exist', ->
      state = new State()
      account1 = state.getAccount 'Peter'
      account2 = state.getAccount 'Peter'
      account2.should.equal account1

    it 'should return different accounts for different IDs', ->
      state = new State()
      accountPeter = state.getAccount 'Peter'
      accountPaul = state.getAccount 'Paul'
      accountPaul.should.not.equal accountPeter

  it 'should instantiate from a known state', ->
    state = new State
      nextId: 1234567890
      accounts: 
        'Peter':
          balances:
            'EUR': '5000'
            'BTC': '50'
        'Paul':
          balances:
            'EUR': '2500'
            'BTC': '75'
    state.getAccount('Peter').getBalance('EUR').getAmount().should.equal '5000'
    state.getAccount('Peter').getBalance('BTC').getAmount().should.equal '50'
    state.getAccount('Paul').getBalance('EUR').getAmount().should.equal '2500'
    state.getAccount('Paul').getBalance('BTC').getAmount().should.equal '75'

  describe '#increaseBalance', ->
    it 'should apply deltas with sequential IDs', ->
      state = new State()
      state.increaseBalance
        id: 0
        account: 'Peter'
        currency: 'EUR'
        amount: '100'
      state.getAccount('Peter').getBalance('EUR').getAmount().should.equal '100'
      state.increaseBalance
        id: 1
        account: 'Peter'
        currency: 'EUR'
        amount: '150'
      state.getAccount('Peter').getBalance('EUR').getAmount().should.equal '250'
      state.increaseBalance
        id: 2
        account: 'Peter'
        currency: 'EUR'
        amount: '50'
      state.getAccount('Peter').getBalance('EUR').getAmount().should.equal '300'

    it 'should ignore increases with an ID lower than expected as such an increase will have already been applied', ->
      state = new State
        nextId: 1234567890
        accounts: 
          'Peter':
            balances:
              'EUR': '5000'
      state.increaseBalance
        id: 1234567889
        account: 'Peter'
        currency: 'EUR'
        amount: '50'
      state.getAccount('Peter').getBalance('EUR').getAmount().should.equal '5000'
