chai = require 'chai'
chai.should()
expect = chai.expect
Checklist = require 'checklist'

Server = require '../../src/Server'

supertest = require 'supertest'
zmq = require 'zmq'
ports = require '../support/ports'
Engine = require('currency-market').Engine
Operation = require('currency-market').Operation
Delta = require('currency-market').Delta
State = require('currency-market').State
Amount = require('currency-market').Amount

request = null
ceOperationHub = null
ceDeltaHub = null
engine = null
state = null
server = null
sequence = 0

COMMISSION_RATE = new Amount '0.001'
COMMISSION_REFERENCE = '0.1%'

applyOperation = (operation) ->
  operation.accept
    sequence: sequence++
    timestamp: Date.now()
  response = 
    operation: operation
  try
    response.delta = engine.apply operation
    state.apply response.delta
    ceDeltaHub.stream.send JSON.stringify response.delta
  catch error
    response.error = error.toString()
  return response

describe 'Server', ->
  beforeEach ->
    httpPort = ports()
    request = supertest 'http://localhost:' + httpPort
    ceOperationHub = zmq.socket 'router'
    ceOperationHubSubmitPort = ports()
    ceOperationHub.bindSync 'tcp://*:' + ceOperationHubSubmitPort
    ceDeltaHub = 
      stream: zmq.socket 'pub'
      state: zmq.socket 'router'
    ceDeltaHubStreamPort = ports()
    ceDeltaHub.stream.bindSync 'tcp://*:' + ceDeltaHubStreamPort
    ceDeltaHubStatePort = ports()
    ceDeltaHub.state.bindSync 'tcp://*:' + ceDeltaHubStatePort
    sequence = 0
    engine = new Engine
      commission:
        account: 'commission'
        calculate: (params) ->
          amount: params.amount.multiply COMMISSION_RATE
          reference: COMMISSION_REFERENCE
    state = new State
      commission:
        account: 'commission'
      json: JSON.stringify engine
    server = new Server
      port: httpPort
      commission:
        account: 'commission'
      'ce-operation-hub':
        host: 'localhost'
        submit: ceOperationHubSubmitPort
      'ce-delta-hub':
        host: 'localhost'
        stream: ceDeltaHubStreamPort
        state: ceDeltaHubStatePort

  afterEach ->
    ceOperationHub.close()
    ceDeltaHub.stream.close()
    ceDeltaHub.state.close()

  describe '#stop', ->
    it 'should error if the server has not been started', (done) ->
      server.stop (error) ->
        error.message.should.equal 'Not running'
        done()

  describe '#start', ->
    it 'should start and be stoppable', (done) ->
      ceDeltaHub.state.on 'message', (ref) =>
        # send the state so that the server can finish starting
        ceDeltaHub.state.send [ref, JSON.stringify state]
      server.start (error) ->
        expect(error).to.not.be.ok
        # request with keep alive to test that the server can stop with open connections
        request
        .get('/')
        .set('Connection', 'Keep-Alive')
        .end (error, response) =>          
          server.stop (error) ->
            expect(error).to.not.be.ok
            done()

  describe 'when started', ->
    beforeEach (done) ->
      checklist = new Checklist [
        'deltas sent'
        'server started'
      ], done
      ceOperationHub.on 'message', (ref, message) =>
        response = applyOperation new Operation
          json: message
        ceOperationHub.send [ref, JSON.stringify response]
      ceDeltaHub.state.on 'message', (ref) =>
        args = Array.apply null, arguments
        # publishing some deltas before sending the state
        applyOperation new Operation
          reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
          account: 'Peter'
          deposit:
            currency: 'EUR'
            amount: new Amount '5000'
        applyOperation new Operation
          reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
          account: 'Peter'
          deposit:
            currency: 'BTC'
            amount: new Amount '50'
        applyOperation new Operation
          reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
          account: 'Paul'
          deposit:
            currency: 'USD'
            amount: new Amount '7500'
        # wait a bit before sending the state to ensure that the previous increases were cached 
        setTimeout =>
          # send the state now which should result in the previous deltas being ignored
          ceDeltaHub.state.send [ref, JSON.stringify state]
          # now send some more deltas
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Peter'
            deposit:
              currency: 'EUR'
              amount: new Amount '2500'
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Peter'
            deposit:
              currency: 'BTC'
              amount: new Amount '75'
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Paul'
            deposit:
              currency: 'USD'
              amount: new Amount '5000'
          # send some deltas for an account not in the sent state
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Tom'
            deposit:
              currency: 'BTC'
              amount: new Amount '2500'
          applyOperation new Operation
            reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
            account: 'Tom'
            deposit:
              currency: 'EUR'
              amount: new Amount '2500'
          # wait a bit so that the state has been received then send some more deltas
          setTimeout =>
            applyOperation new Operation
              reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
              account: 'Peter'
              deposit:
                currency: 'BTC'
                amount: new Amount '75'
            applyOperation new Operation
              reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
              account: 'Paul'
              deposit:
                currency: 'USD'
                amount: new Amount '5000'
            applyOperation new Operation
              reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
              account: 'Tom'
              deposit:
                currency: 'BTC'
                amount: new Amount '2500'
            checklist.check 'deltas sent'
          , 250
        , 250
      # send some deltas before the server starts
      applyOperation new Operation
        reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
        account: 'Peter'
        deposit:
          currency: 'EUR'
          amount: new Amount '2500'
      applyOperation new Operation
        reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
        account: 'Peter'
        deposit:
          currency: 'BTC'
          amount: new Amount '25'
      applyOperation new Operation
        reference: 'faaa22e0-e8a8-11e2-91e2-0800200c9a66'
        account: 'Peter'
        deposit:
          currency: 'USD'
          amount: new Amount '2500'
      server.start (error) =>
        checklist.check 'server started'

    afterEach (done) ->
      server.stop (error) =>
        done error

    describe 'GET /hal/browser.html', ->
      it 'should serve the HAL browser', (done) ->
        request
        .get('/hal/browser.html')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect /The HAL Browser/, done

    describe 'GET /', ->
      it 'should return the root of the hypermedia API', (done) ->
        request
        .get('/')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:accounts'].href.should.equal '/accounts'
          halResponse._links['ce:books'].href.should.equal '/books'
          done()

    describe 'GET /rels/accounts', ->
      it 'should return the accounts relationship documentation', (done) ->
        # The first templated response seems to take a while
        # I guess it is loading and caching modules
        @timeout 5000
        request
        .get('/rels/accounts')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/ce:accounts/)
        .expect(/GET/)
        .expect(/Fetch a list of accounts/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/Links/)
        .expect(/ce:account/)
        .expect(/\/rels\/account/)
        .expect(/an array of account links/)
        .end done

    describe 'GET /rels/books', ->
      it 'should return the books relationship documentation', (done) ->
        # The first templated response seems to take a while
        # I guess it is loading and caching modules
        @timeout 5000
        request
        .get('/rels/books')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/ce:books/)
        .expect(/GET/)
        .expect(/Fetch a list of collections of books by bid currency/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/Links/)
        .expect(/ce:books-by-bid-currency/)
        .expect(/\/rels\/books-by-bid-currency/)
        .expect(/an array of links to collections of books by bid currency/)
        .end done

    describe 'GET /accounts', ->
      it 'should return the list of accounts', (done) ->
        checks = for id of state.accounts
          id
        checklist = new Checklist checks, done
        request
        .get('/accounts')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          accounts = halResponse._links['ce:account']
          for account in accounts
            account.href.should.equal '/accounts/' + account.name
            checklist.check account.name

    describe 'GET /rels/account', ->
      it 'should return the account relationship documentation', (done) ->
        # The first templated response seems to take a while
        # I guess it is loading and caching modules
        @timeout 5000
        request
        .get('/rels/account')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/ce:account/)
        .expect(/GET/)
        .expect(/Fetch an account state/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/Links/)
        .expect(/ce:balances/)
        .expect(/\/rels\/balances/)
        .expect(/link to the collection of currency balances/)
        .expect(/ce:deposits/)
        .expect(/\/rels\/deposits/)
        .expect(/link to the collection of logged deposits/)
        .expect(/ce:withdrawals/)
        .expect(/\/rels\/withdrawals/)
        .expect(/link to the collection of logged withdrawals/)
        .expect(/ce:orders/)
        .expect(/\/rels\/orders/)
        .expect(/link to the collection of active orders/)
        .end done

    describe 'GET /accounts/:id', ->
      it 'should return a blank account if no account exists', (done) ->
        request
        .get('/accounts/Unknown')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:balances'].href.should.equal '/accounts/Unknown/balances'
          halResponse._links['ce:deposits'].href.should.equal '/accounts/Unknown/deposits'
          halResponse._links['ce:withdrawals'].href.should.equal '/accounts/Unknown/withdrawals'
          halResponse._links['ce:orders'].href.should.equal '/accounts/Unknown/orders'
          done()

      it 'should return an existing account', (done) ->
        request
        .get('/accounts/Peter')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Peter'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:balances'].href.should.equal '/accounts/Peter/balances'
          halResponse._links['ce:deposits'].href.should.equal '/accounts/Peter/deposits'
          halResponse._links['ce:withdrawals'].href.should.equal '/accounts/Peter/withdrawals'
          halResponse._links['ce:orders'].href.should.equal '/accounts/Peter/orders'
          done()

    describe 'GET /rels/balances', ->
      it 'should return the balances relationship documentation', (done) ->
        # The first templated response seems to take a while
        # I guess it is loading and caching modules
        @timeout 5000
        request
        .get('/rels/balances')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/ce:balances/)
        .expect(/GET/)
        .expect(/Fetch the list of currency balances for the account/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/Links/)
        .expect(/ce:balance/)
        .expect(/\/rels\/balance/)
        .expect(/an array of links to balances in each currency/)
        .end done

    describe 'GET /rels/deposits', ->
      it 'should return the deposits relationship documentation', (done) ->
        # The first templated response seems to take a while
        # I guess it is loading and caching modules
        @timeout 5000
        request
        .get('/rels/deposits')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/ce:deposits/)
        .expect(/GET/)
        .expect(/Fetch the list of logged deposits for the account/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/Links/)
        .expect(/ce:deposit/)
        .expect(/\/rels\/deposit/)
        .expect(/an array of links to logged deposits/)
        .expect(/POST/)
        .expect(/Deposit funds into an account/)
        .expect(/Request/)
        .expect(/Deposit 5000 Euros/)
        .expect(/&quot;currency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;amount&quot;: &quot;5000&quot;/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/After successfully applying the deposit operation a delta will be received giving the new funds available in the relevent account balance/)
        .expect(/&quot;operation&quot;:/)
        .expect(/&quot;sequence&quot;: 123456789/)
        .expect(/&quot;timestamp&quot;: 13789945543/)
        .expect(/&quot;account&quot;: &quot;AccountId&quot;/)
        .expect(/&quot;deposit&quot;:/)
        .expect(/&quot;currency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;amount&quot;: &quot;5000&quot;/)
        .expect(/&quot;result&quot;:/)
        .expect(/&quot;funds&quot;: &quot;123456787.454&quot;/)
        .expect(/When the deposit operation takes too long a pending flag will be received. The deposit may still succeed at a later time/)
        .expect(/&quot;operation&quot;:/)
        .expect(/&quot;sequence&quot;: 123456789/)
        .expect(/&quot;timestamp&quot;: 13789945543/)
        .expect(/&quot;account&quot;: &quot;AccountId&quot;/)
        .expect(/&quot;deposit&quot;:/)
        .expect(/&quot;currency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;amount&quot;: &quot;5000&quot;/)
        .expect(/&quot;pending&quot;: true/)
        .expect(/When an error is encountered applying the deposit operation the error message will be received/)
        .expect(/&quot;operation&quot;:/)
        .expect(/&quot;sequence&quot;: 123456789/)
        .expect(/&quot;timestamp&quot;: 13789945543/)
        .expect(/&quot;account&quot;: &quot;AccountId&quot;/)
        .expect(/&quot;deposit&quot;:/)
        .expect(/&quot;currency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;amount&quot;: &quot;5000&quot;/)
        .expect(/&quot;error&quot;: &quot;Error: some error&quot;/)
        .end done

    describe 'GET /rels/withdrawals', ->
      it 'should return the withdrawals relationship documentation', (done) ->
        # The first templated response seems to take a while
        # I guess it is loading and caching modules
        @timeout 5000
        request
        .get('/rels/withdrawals')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/ce:withdrawals/)
        .expect(/GET/)
        .expect(/Fetch the list of logged withdrawals for the account/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/Links/)
        .expect(/ce:withdrawal/)
        .expect(/\/rels\/withdrawal/)
        .expect(/an array of links to logged withdrawals/)
        .expect(/POST/)
        .expect(/Withdraw funds from an account/)
        .expect(/Request/)
        .expect(/Withdraw 5000 Euros/)
        .expect(/&quot;currency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;amount&quot;: &quot;5000&quot;/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/After successfully applying the withdraw operation a delta will be received giving the new funds available in the relevent account balance/)
        .expect(/&quot;operation&quot;:/)
        .expect(/&quot;sequence&quot;: 123456789/)
        .expect(/&quot;timestamp&quot;: 13789945543/)
        .expect(/&quot;account&quot;: &quot;AccountId&quot;/)
        .expect(/&quot;withdraw&quot;:/)
        .expect(/&quot;currency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;amount&quot;: &quot;5000&quot;/)
        .expect(/&quot;result&quot;:/)
        .expect(/&quot;funds&quot;: &quot;123456787.454&quot;/)
        .expect(/When the withdraw operation takes too long a pending flag will be received. The withdrawal may still succeed at a later time/)
        .expect(/&quot;operation&quot;:/)
        .expect(/&quot;sequence&quot;: 123456789/)
        .expect(/&quot;timestamp&quot;: 13789945543/)
        .expect(/&quot;account&quot;: &quot;AccountId&quot;/)
        .expect(/&quot;withdraw&quot;:/)
        .expect(/&quot;currency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;amount&quot;: &quot;5000&quot;/)
        .expect(/&quot;pending&quot;: true/)
        .expect(/When an error is encountered applying the withdraw operation the error message will be received/)
        .expect(/&quot;operation&quot;:/)
        .expect(/&quot;sequence&quot;: 123456789/)
        .expect(/&quot;timestamp&quot;: 13789945543/)
        .expect(/&quot;account&quot;: &quot;AccountId&quot;/)
        .expect(/&quot;withdraw&quot;:/)
        .expect(/&quot;currency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;amount&quot;: &quot;5000&quot;/)
        .expect(/&quot;error&quot;: &quot;Error: some error&quot;/)
        .end done

    describe 'GET /rels/orders', ->
      it 'should return the orders relationship documentation', (done) ->
        # The first templated response seems to take a while
        # I guess it is loading and caching modules
        @timeout 5000
        request
        .get('/rels/orders')
        .set('Accept', 'text/html')
        .expect(200)
        .expect('Content-Type', /html/)
        .expect(/ce:orders/)
        .expect(/GET/)
        .expect(/Fetch the list of active orders for the account/)
        .expect(/Responses/)
        .expect(/200 OK/)
        .expect(/Links/)
        .expect(/ce:order/)
        .expect(/\/rels\/order/)
        .expect(/an array of links to active orders/)
        .expect(/POST/)
        .expect(/Submit a new order to the market/)
        .expect(/Request/)
        .expect(/For bid orders specify the bid price as the amount of the offer currency being bid for 1 unit of the bid currency and a bid amount as the number of units of the bid currency being requested/)        
        .expect(/&quot;bidCurrency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;offerCurrency&quot;: &quot;BTC&quot;/)
        .expect(/&quot;bidPrice&quot;: &quot;0.01&quot;/)
        .expect(/&quot;bidAmount&quot;: &quot;5000&quot;/)
        .expect(/For offer orders specify the offer price as the amount of the bid currency required for 1 unit of the offer currency and an offer amount as the number of units of the offer currency being offered/)        
        .expect(/&quot;bidCurrency&quot;: &quot;EUR&quot;/)
        .expect(/&quot;offerCurrency&quot;: &quot;BTC&quot;/)
        .expect(/&quot;offerPrice&quot;: &quot;100&quot;/)
        .expect(/&quot;offerAmount&quot;: &quot;50&quot;/)
        .end done

    describe 'POST /accounts/:id/deposits', ->
      it 'should respond with the new list of deposits setting the optional new property for the new deposit', (done) ->
        balance = state.getAccount('Peter').getBalance('EUR')
        expectedFunds = balance.funds.add new Amount '50'
        request
        .post('/accounts/Peter/deposits')
        .set('Accept', 'application/hal+json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balance.funds.compareTo(expectedFunds).should.equal 0
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Peter/deposits'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          # TODO: haven't implemented logged deposits yet
          halResponse._links['ce:deposit'].should.have.length 0
          request
          .get('/accounts/Peter/balances/EUR')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse.funds.should.equal balance.funds.toString()
            done()

      it.skip 'should respond with a 422 error if the deposit is not a valid request', (done) ->
        done()

      it.skip 'should respond with a 502 error if the deposit results in an unknown error from upstream components', (done) ->
        done()

      it.skip 'should respond with a 504 error if the deposit results in a server side timeout', (done) ->
        done()


    describe 'GET /accounts/:id/deposits', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/accounts/Unknown/deposits')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/deposits'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:deposit'].should.have.length 0
          done()

      it.skip 'should return the deposits logged for the account', (done) ->
        request
        .post('/accounts/Peter/deposits')
        .set('Accept', 'application/json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .get('/accounts/Peter/deposits')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/Peter/deposits'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse._links['ce:deposit'].should.have.length 10
            done()

    describe 'POST /accounts/:id/withdrawals', ->
      it 'should respond with the new list of withdrawals setting the optional new property for the new withdrawal', (done) ->
        balance = state.getAccount('Peter').getBalance('EUR')
        expectedFunds = balance.funds.subtract new Amount '50'
        request
        .post('/accounts/Peter/withdrawals')
        .set('Accept', 'application/hal+json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balance.funds.compareTo(expectedFunds).should.equal 0
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Peter/withdrawals'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          # TODO: haven't implemented logged withdrawals yet
          halResponse._links['ce:withdrawal'].should.have.length 0
          request
          .get('/accounts/Peter/balances/EUR')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse.funds.should.equal balance.funds.toString()
            done()

      it.skip 'should respond with a 422 error if the withdrawal is not a valid request', (done) ->
        done()

      it.skip 'should respond with a 502 error if the withdrawal results in an unknown error from upstream components', (done) ->
        done()

      it.skip 'should respond with a 504 error if the withdrawal results in a server side timeout', (done) ->
        done()

      it.skip 'should respond with a 428 error if the withdrawal is a valid request but cannot be applied to the market because the funds are not available', (done) ->
        done()

    describe 'GET /accounts/:id/withdrawals', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/accounts/Unknown/withdrawals')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/withdrawals'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:withdrawal'].should.have.length 0
          done()

      it.skip 'should return the withdrawals logged for the account', (done) ->
        request
        .post('/accounts/Peter/withdrawals')
        .set('Accept', 'application/json')
        .send
          currency: 'EUR'
          amount: '50'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .get('/accounts/Peter/withdrawals')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/Peter/withdrawals'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse._links['ce:withdrawal'].should.have.length 1
            done()

    describe 'GET /accounts/:id/balances', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/accounts/Unknown/balances')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/balances'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:balance'].should.have.length 0
          done()

      it 'should return the account balances received from the ce-delta-hub', (done) ->
        checks = for id of state.accounts
          id
        checklist = new Checklist checks, done
        # can't use for .. of here as it doesn't play nice with closures
        Object.keys(state.accounts).forEach (id) =>
          account = state.accounts[id]
          request
          .get('/accounts/' + id + '/balances')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/' + id + '/balances'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            if account.balances.length > 0
              checks = []
              for currency of account.balances
                checks.push currency
              balancesChecklist = new Checklist checks, (error) =>
                if error
                  checklist.check error
                else
                  checklist.check id
              balances = halResponse._links['ce:balance']
              for balance in balances
                balance.href.should.equal '/accounts/' + id + '/balances/' + balance.name
                balancesChecklist.check balance.name
            else
              checklist.check id

    describe 'GET /accounts/:id/balances/:currency', ->
      it 'should return 0 funds and locked funds for uninitialised balances', (done) ->
        request
        .get('/accounts/Unknown/balances/EUR')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/balances/EUR'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse.funds.should.equal '0'
          halResponse.lockedFunds.should.equal '0'
          done()

      it 'should return the account balance received from the ce-delta-hub', (done) ->
        checks = []
        for id, account of state.accounts
          for currency of account.balances
            checks.push id + currency
        checklist = new Checklist checks, done
        # can't use for .. in here as it doesn't play nice with closures
        Object.keys(state.accounts).forEach (id) =>
          account = state.accounts[id]
          Object.keys(account.balances).forEach (currency) =>
            expectedFunds = account.balances[currency].funds.toString()
            expectedLockedFunds = account.balances[currency].lockedFunds.toString()
            request
            .get('/accounts/' + id + '/balances/' + currency)
            .set('Accept', 'application/hal+json')
            .expect(200)
            .expect('Content-Type', /hal\+json/)
            .end (error, response) =>
              expect(error).to.not.be.ok
              halResponse = JSON.parse response.text
              halResponse._links.self.href.should.equal '/accounts/' + id + '/balances/' + currency
              halResponse._links.curie.name.should.equal 'ce'
              halResponse._links.curie.href.should.equal '/rels/{rel}'
              halResponse._links.curie.templated.should.be.true
              halResponse.funds.should.equal expectedFunds
              halResponse.lockedFunds.should.equal expectedLockedFunds
              checklist.check id + currency

    describe 'POST /accounts/:id/orders', ->
      it 'should respond with the new list of orders setting the optional newOrder property for the new order', (done) ->
        account = state.getAccount 'Peter'
        balance = account.getBalance 'EUR'
        orders = account.orders
        book = state.getBook
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/hal+json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
          bidPrice: '100'
          bidAmount: '50'
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balance.lockedFunds.compareTo(new Amount '5000').should.equal 0
          halResponse = JSON.parse response.text
          halResponse.newOrder.should.equal '' + 14
          halResponse._links.self.href.should.equal '/accounts/Peter/orders'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:order'].should.have.length 1
          order = halResponse._links['ce:order'][0]
          order.name.should.equal '' + 14
          order.href.should.equal '/accounts/Peter/orders/' + order.name
          book[0].should.equal orders[14]
          done()

      it.skip 'should respond with a 422 error if the order is not a valid request', (done) ->
        done()

      it.skip 'should respond with a 502 error if the order results in an unknown error from upstream components', (done) ->
        done()

      it.skip 'should respond with a 504 error if the order results in a server side timeout', (done) ->
        done()

      it 'should respond with a 428 "Precondition Required" error if the order is a valid request but cannot be applied to the market because the funds are not available', (done) ->
        account = state.getAccount 'Peter'
        balance = account.getBalance 'EUR'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/hal+json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'GBP'
          bidPrice: '100'
          bidAmount: '50'
        .expect(428)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          balance.lockedFunds.compareTo(new Amount '0').should.equal 0
          halResponse = JSON.parse response.text
          halResponse.error.should.equal 'Error: Cannot lock funds that are not available'
          halResponse._links.self.href.should.equal '/accounts/Peter/orders'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:order'].should.have.length 0
          done()

    describe 'GET /accounts/:id/orders', ->
      it 'should return an empty object for unknown accounts', (done) ->
        request
        .get('/accounts/Unknown/orders')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/accounts/Unknown/orders'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:order'].should.have.length 0
          done()

      it 'should return the logged (active or archived) orders for the account', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/hal+json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          request
          .post('/accounts/Peter/orders')
          .set('Accept', 'application/hal+json')
          .send
            bidCurrency: 'USD'
            offerCurrency: 'EUR'
            bidPrice: '0.5'
            bidAmount: '5000'
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            request
            .post('/accounts/Peter/orders')
            .set('Accept', 'application/hal+json')
            .send
              bidCurrency: 'BTC'
              offerCurrency: 'USD'
              bidPrice: '50'
              bidAmount: '25'
            .expect(200)
            .expect('Content-Type', /hal\+json/)
            .end (error, response) =>
              expect(error).to.not.be.ok
              request
              .get('/accounts/Peter/orders')
              .set('Accept', 'application/hal+json')
              .expect(200)
              .expect('Content-Type', /hal\+json/)
              .end (error, response) =>
                expect(error).to.not.be.ok
                halResponse = JSON.parse response.text
                halResponse._links.self.href.should.equal '/accounts/Peter/orders'
                halResponse._links.curie.name.should.equal 'ce'
                halResponse._links.curie.href.should.equal '/rels/{rel}'
                halResponse._links.curie.templated.should.be.true
                halResponse._links['ce:order'].should.have.length 3
                for order, index in halResponse._links['ce:order']
                  order.href.should.equal '/accounts/Peter/orders/' + order.name
                  order.name.should.equal '' + (index + 14)
                # TODO: also check for archived orders which should include any that
                # have been completely executed, partially executed and cancelled, and maybe
                # those that were not executed at all and cancelled (not sure about the last one)
                done()

    describe 'GET /accounts/:id/orders/:sequence', ->
      it 'should return 404 error for unknown orders', (done) ->
        request
        .get('/accounts/Peter/orders/1234165')
        .set('Accept', 'application/hal+json')
        .expect 404, done

      it 'should return the order details including the active state and a list of trades that were applied against the order', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/hal+json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          halResponse = JSON.parse response.text
          orderSequence = halResponse.newOrder
          request
          .get('/accounts/Peter/orders/' + halResponse.newOrder)
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/Peter/orders/' + orderSequence
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse.sequence.should.equal parseInt orderSequence
            halResponse.timestamp.should.be.a 'number'
            halResponse.account.should.equal 'Peter'
            halResponse.bidCurrency.should.equal 'EUR'
            halResponse.offerCurrency.should.equal 'BTC'
            halResponse.bidPrice.should.equal '0.01'
            halResponse.bidAmount.should.equal '5000'
            # TODO: active flag and trades
            done()

    describe 'DELETE /accounts/:id/orders/:sequence', ->
      it 'should respond with the new list of orders', (done) ->
        account = state.getAccount 'Peter'
        balance = account.getBalance 'EUR'
        orders = account.orders
        book = state.getBook
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/hal+json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
          bidPrice: '100'
          bidAmount: '50'
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          halResponse = JSON.parse response.text
          request
          .del('/accounts/Peter/orders/' + halResponse.newOrder)
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            balance.lockedFunds.compareTo(new Amount '0').should.equal 0
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/accounts/Peter/orders'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse._links['ce:order'].should.have.length 0
            Object.keys(orders).should.have.length 0
            book.should.have.length 0
            done()

      it.skip 'should respond with a 422 error if the cancellation is not a valid request', (done) ->
        done()

      it.skip 'should respond with a 502 error if the cancellation results in an unknown error from upstream components', (done) ->
        done()

      it.skip 'should respond with a 504 error if the cancellation results in a server side timeout', (done) ->
        done()

      it 'should respond with a 428 "Precondition Required" error if the order is not active (already cancelled, executed, etc)', (done) ->
        request
        .del('/accounts/Peter/orders/1234165')
        .set('Accept', 'application/hal+json')
        .expect(428)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse.error.should.equal 'Error: Order is not active'
          halResponse._links.self.href.should.equal '/accounts/Peter/orders'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:order'].should.have.length 0
          done()

    describe 'GET /books', ->
      it 'should return an empty list if no books exist', (done) ->
        request
        .get('/books')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/books'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:books-by-bid-currency'].should.have.length 0
          done()

      it 'should return the list of collections of books by bid currency', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/hal+json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .post('/accounts/Peter/orders')
          .set('Accept', 'application/hal+json')
          .send
            bidCurrency: 'USD'
            offerCurrency: 'EUR'
            bidPrice: '0.5'
            bidAmount: '5000'
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            request
            .post('/accounts/Peter/orders')
            .set('Accept', 'application/hal+json')
            .send
              bidCurrency: 'BTC'
              offerCurrency: 'USD'
              bidPrice: '50'
              bidAmount: '25'
            .expect(200)
            .expect('Content-Type', /hal\+json/)
            .end (error, response) =>
              checks = for currency of state.books
                currency
              checks.should.have.length 3
              checklist = new Checklist checks, done
              request
              .get('/books')
              .set('Accept', 'application/hal+json')
              .expect(200)
              .expect('Content-Type', /hal\+json/)
              .end (error, response) =>
                expect(error).to.not.be.ok
                halResponse = JSON.parse response.text
                halResponse._links.self.href.should.equal '/books'
                halResponse._links.curie.name.should.equal 'ce'
                halResponse._links.curie.href.should.equal '/rels/{rel}'
                halResponse._links.curie.templated.should.be.true
                booksByBidCurrency = halResponse._links['ce:books-by-bid-currency']
                for books in booksByBidCurrency
                  books.href.should.equal '/books/' + books.name
                  checklist.check books.name

    describe 'GET /books/:bidCurrency', ->
      it 'should return an empty list if no books exist', (done) ->
        request
        .get('/books/EUR')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/books/EUR'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:book'].should.have.length 0
          done()

      it 'should return the list of collections of books by bid currency', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'GBP'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .post('/accounts/Peter/orders')
          .set('Accept', 'application/json')
          .send
            bidCurrency: 'GBP'
            offerCurrency: 'EUR'
            bidPrice: '0.5'
            bidAmount: '5000'
          .expect(200)
          .expect('Content-Type', /json/)
          .end (error, response) =>
            request
            .post('/accounts/Peter/orders')
            .set('Accept', 'application/json')
            .send
              bidCurrency: 'GBP'
              offerCurrency: 'USD'
              bidPrice: '50'
              bidAmount: '25'
            .expect(200)
            .expect('Content-Type', /json/)
            .end (error, response) =>
              books = state.getBooks 'GBP'
              checks = for currency of books
                currency
              checks.should.have.length 3
              checklist = new Checklist checks, done
              request
              .get('/books/GBP')
              .set('Accept', 'application/hal+json')
              .expect(200)
              .expect('Content-Type', /hal\+json/)
              .end (error, response) =>
                expect(error).to.not.be.ok
                halResponse = JSON.parse response.text
                halResponse._links.self.href.should.equal '/books/GBP'
                halResponse._links.curie.name.should.equal 'ce'
                halResponse._links.curie.href.should.equal '/rels/{rel}'
                halResponse._links.curie.templated.should.be.true
                booksByOfferCurrency = halResponse._links['ce:book']
                for books in booksByOfferCurrency
                  books.href.should.equal '/books/GBP/' + books.name
                  checklist.check books.name

    describe 'GET /books/:bidCurrency/:offerCurrency', ->
      it 'should return an empty list of orders for an unknown book', (done) ->
        request
        .get('/books/Unknown/Unknown')
        .set('Accept', 'application/hal+json')
        .expect(200)
        .expect('Content-Type', /hal\+json/)
        .end (error, response) =>
          expect(error).to.not.be.ok
          halResponse = JSON.parse response.text
          halResponse._links.self.href.should.equal '/books/Unknown/Unknown'
          halResponse._links.curie.name.should.equal 'ce'
          halResponse._links.curie.href.should.equal '/rels/{rel}'
          halResponse._links.curie.templated.should.be.true
          halResponse._links['ce:order-by-book'].should.have.length 0
          done()

      it 'should return a list of active orders for a book', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'BTC'
          offerCurrency: 'EUR'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          request
          .post('/accounts/Tom/orders')
          .set('Accept', 'application/json')
          .send
            bidCurrency: 'BTC'
            offerCurrency: 'EUR'
            offerPrice: '0.01'
            offerAmount: '2500'
          .expect(200)
          .expect('Content-Type', /json/)
          .end (error, response) =>
            request
            .get('/books/BTC/EUR')
            .set('Accept', 'application/hal+json')
            .expect(200)
            .expect('Content-Type', /hal\+json/)
            .end (error, response) =>
              expect(error).to.not.be.ok
              halResponse = JSON.parse response.text
              halResponse._links.self.href.should.equal '/books/BTC/EUR'
              halResponse._links.curie.name.should.equal 'ce'
              halResponse._links.curie.href.should.equal '/rels/{rel}'
              halResponse._links.curie.templated.should.be.true
              halResponse._links['ce:order-by-book'].should.have.length 2
              for order, index in halResponse._links['ce:order-by-book']
                order.href.should.equal '/books/BTC/EUR/' + index
                order.name.should.equal '' + index
              done()

    describe 'GET /books/:bidCurrency/:offerCurrency/:index', ->
      it 'should return 404 error for unknown indices', (done) ->
        request
        .get('/books/BTC/EUR/1234165')
        .set('Accept', 'application/hal+json')
        .expect 404, done

      it 'should return the order details', (done) ->
        request
        .post('/accounts/Peter/orders')
        .set('Accept', 'application/json')
        .send
          bidCurrency: 'EUR'
          offerCurrency: 'BTC'
          bidPrice: '0.01'
          bidAmount: '5000'
        .expect(200)
        .expect('Content-Type', /json/)
        .end (error, response) =>
          halResponse = JSON.parse response.text
          orderSequence = halResponse.newOrder
          request
          .get('/books/EUR/BTC/0')
          .set('Accept', 'application/hal+json')
          .expect(200)
          .expect('Content-Type', /hal\+json/)
          .end (error, response) =>
            expect(error).to.not.be.ok
            halResponse = JSON.parse response.text
            halResponse._links.self.href.should.equal '/books/EUR/BTC/0'
            halResponse._links.curie.name.should.equal 'ce'
            halResponse._links.curie.href.should.equal '/rels/{rel}'
            halResponse._links.curie.templated.should.be.true
            halResponse.sequence.should.equal parseInt orderSequence
            halResponse.timestamp.should.be.a 'number'
            halResponse.account.should.equal 'Peter'
            halResponse.bidCurrency.should.equal 'EUR'
            halResponse.offerCurrency.should.equal 'BTC'
            halResponse.bidPrice.should.equal '0.01'
            halResponse.bidAmount.should.equal '5000'
            done()              
