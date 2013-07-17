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
  // Optional: account that receives commission
  "commission": {
    "account": "commission"
  },
  // Submits operations to and receives operation results from the configured `ce-operation-hub`
  "ce-operation-hub": {
    "host": "localhost",
    // Port for 0MQ `dealer` socket
    "submit": 8001
  },
  // Requests market state and receives market deltas streamed from the configured `ce-delta-hub`
  "ce-delta-hub": {
    "host": "localhost",
    // Port for 0MQ `sub` socket
    "stream": 8002,
    // Port for 0MQ `dealer` socket
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

## Hypermedia API

Starting at the root `/` it should be possible to completely browse the API which has been impelemnted using the HAL standard.
A HAL browser is exposed at `/hal/browser.html`

## Roadmap

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
