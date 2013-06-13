Amount = require './Amount'

module.exports = class Balance

  constructor: (amount) ->
    if amount
      @amount = new Amount amount
    else
      @amount = Amount.ZERO

  increase: (amount) =>
    @amount = @amount.add new Amount amount

  getAmount: =>
    @amount.toString()