ce-front-end
============

[![Build Status](https://travis-ci.org/pghalliday/ce-front-end.png?branch=master)](https://travis-ci.org/pghalliday/ce-front-end)
[![Dependency Status](https://gemnasium.com/pghalliday/ce-front-end.png)](https://gemnasium.com/pghalliday/ce-front-end)

Front end implementation for currency exchange service.

## Configuration

configuration should be placed in a file called `config.json` in the root of the project

```javascript
{
  // Port for HTTP/REST API
  "port": 8000,
  // Submits operations to and receives operation results from the configured `ce-operation-hub`
  "ce-operation-hub": {
    "host": "localhost",
    // Port for 0MQ `xreq` socket
    "submit": 8001
  },
  // Requests market state and receives market deltas streamed from the configured `ce-delta-hub`
  "ce-delta-hub": {
    "host": "localhost",
    // Port for 0MQ `sub` socket
    "stream": 8002,
    // Port for 0MQ `xreq` socket
    "state": 8003
  }
}
```

## Starting and stopping the server

Forever is used to keep the server running as a daemon and can be called through npm as follows

```
$ npm start
$ npm stop
```

Output will be logged to the following files

- `~/.forever/forever.log` Forever output
- `./out.log` stdout
- `./err.log` stderr

## REST API

#### `GET /balances/[account]/`

Query an account's balances

Response:

```javascript
{
  "EUR": "5000",
  "BTC": "50"
}
```

#### `GET /balances/[account]/[currency]`

Query an account's balance in a particular currency

Response:

```javascript
"5000"
```

#### `POST /deposits/[account]/`

Deposit funds into an account

Request:

```javascript
{
  "currency": "EUR",
  "amount": "5000"
}
```

Response:

```javascript
{
  "account": "[account]",
  "id": "1234567890",
  "result": "success",
  "deposit": {
    "currency": "EUR",
    "amount": "5000"
  }
}
```

##### Operations

The following operations may be triggered synchronously

- `deposit`

##### Deltas

The following deltas may be received asynchronously

- `increase` - resulting from the balance increase

#### `POST /orders/[account]/`

Add an order to a book

Request:

```javascript
{
  "bidCurrency": "BTC",
  "offerCurrency": "EUR",
  "bidPrice": "100",
  "bidAmount": "50"
}
```

Response:

```javascript
{
  "account": "[account]",
  "id": "1234567890",
  "result": "success",
  "order": {
    "bidCurrency": "BTC",
    "offerCurrency": "EUR",
    "bidPrice": "100",
    "bidAmount": "50"
  }
}
```

##### Operations

The following operations may be triggered synchronously

- `order`

##### Deltas

The following deltas may be received asynchronously

- `add` - resulting from the addition of the order
- `trade` - resulting from trades executed as a result of adding the order

## Roadmap

### REST API

#### `POST /withdrawals/[account]/`

Withdraw funds

#### `DELETE /orders/[account]/[id]`

Cancel an order

#### `GET /books/[bid-currency]/[offer-currency]/`

Query order book state

#### `GET /deltas/`

Query delta history

- Deltas include
  - trades
  - addition, update or removal of orders
- Deltas should have a sequence ID and this interface should accept a last sequence ID parameter to send deltas after that sequence ID
- Should be able to specify (default to include nothing)
  - list of bid currencies to include
  - list of order currencies to include
  - include trades
  - include order book changes

#### `GET /orders/[account]/`

Query the account outstanding orders

#### `GET /trades/[account]/`

Query the account trade history

#### `GET /withdrawals/[account]/`

Query the account withdrawal history

#### `GET /deposits/[account]/`

Query the account deposit history

#### `POST /accounts/`

Create an account

#### `PUT /accounts/[account]`

Update account details

### Validation

All operations and queries should be validated before forwarding

- Account valid?
- Fields valid?

### Authentication

- local authentication
- 2 factor authentication (TOTP)
- admin authenticated
  - `POST /deposits/[account]/`
- user authenticated
  - `POST /orders/[account]/`
  - `POST /withdrawals/[account]/`
  - `DELETE /orders/[account]/[id]`
  - `GET /balances/[account]/`
  - `GET /orders/[account]/`
  - `GET /trades/[account]/`
  - `GET /withdrawals/[account]/`
  - `GET /deposits/[account]/`

## Contributing
In lieu of a formal styleguide, take care to maintain the existing coding style. Add unit tests for any new or changed functionality. Test your code using: 

```
$ npm test
```

### Using Vagrant
To use the Vagrantfile you will also need to install the following vagrant plugins

```
$ vagrant plugin install vagrant-omnibus
$ vagrant plugin install vagrant-berkshelf
```

The cookbook used by vagrant is located in a git submodule so you will have to intialise that after cloning

```
$ git submodule init
$ git submodule update
```

## License
Copyright &copy; 2013 Peter Halliday  
Licensed under the MIT license.
