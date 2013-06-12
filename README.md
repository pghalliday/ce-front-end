ce-front-end
============

[![Build Status](https://travis-ci.org/pghalliday/ce-front-end.png?branch=master)](https://travis-ci.org/pghalliday/ce-front-end)
[![Dependency Status](https://gemnasium.com/pghalliday/ce-front-end.png)](https://gemnasium.com/pghalliday/ce-front-end)

Front end implementation for currency exchange service.

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

## Configuration


configuration should be placed in a file called `config.json` in the root of the project

```javascript
{
  // Listens for operations and queries over HTTP on the configured `port`
  "port": 3000,
  // Forwards operations to the configured `ce-operation-hub` using 0MQ `XREQ` socket
  "ce-operation-hub": "tcp://ce-operation-hub:4000"
}
```

## REST API

#### `POST /deposits/[account]/`

Deposit funds into an account

```javascript
// Send
{
  "currency": "EUR",
  "amount": "5000"
}

// Response
{
  "currency": "EUR",
  "amount": "5000",
  "id": 123456789,
  "status": "success"
}
```

#### `POST /orders/[account]/`

Add an order to a book

```javascript
// Send
{
  "bidCurrency": "BTC",
  "offerCurrency": "EUR",
  "bidPrice": "100",
  "bidAmount": "50"
}

// Response
{
  "bidCurrency": "BTC",
  "offerCurrency": "EUR",
  "bidPrice": "100",
  "bidAmount": "50",
  "id": 123456789,
  "status": "success"
}
```

## Roadmap

### REST API

#### `GET /balances/[account]/`

Query the account balances

```javascript
// Response
{
  "EUR": "5000",
  "BTC": "50"
}
```

#### `POST /withdrawals/[account]/`

Withdraw funds

#### `DELETE /orders/[account]/[id]`

Cancel an order

#### `GET /books/[bid-currency]/[offer-currency]/`

Query order book state

#### `GET /deltas/`

Query delta history including

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

Query the accoutn deposit history

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
