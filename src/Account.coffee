Balance = require './Balance'

module.exports = class Account
  constructor: (account) ->
    @balances = Object.create null
    if account
      for currency, amount of account.balances
        @balances[currency] = new Balance amount

  getBalance: (currency) =>
    @balances[currency] = @balances[currency] || new Balance()
