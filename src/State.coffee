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

  apply: (delta) =>
    if delta.id == @nextId
      @nextId++
      operation = delta.operation
      if operation
        account = @getAccount(operation.account)
        deposit = operation.deposit
        if deposit
          account.getBalance(deposit.currency).increase deposit.amount
        else
          console.error 'Unknown operation received:'
          console.error delta
      else
        console.error 'Unknown delta received:'
        console.error delta
