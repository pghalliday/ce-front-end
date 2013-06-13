Account = require './Account'

module.exports = class State
  constructor: (state) ->
    @accounts = Object.create null
    @nextId = 0
    if state
      @nextId = state.nextId
      for id, account of state.accounts
        @accounts[id] = new Account account

  getAccount: (id) =>
    @accounts[id] = @accounts[id] || new Account()

  increaseBalance: (increase) =>
    if increase.id == @nextId
      @nextId++
      @getAccount(increase.account).getBalance(increase.currency).increase increase.amount
