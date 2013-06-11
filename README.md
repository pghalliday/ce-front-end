ce-front-end
============

[![Build Status](https://travis-ci.org/pghalliday/ce-front-end.png?branch=master)](https://travis-ci.org/pghalliday/ce-front-end)
[![Dependency Status](https://gemnasium.com/pghalliday/ce-front-end.png)](https://gemnasium.com/pghalliday/ce-front-end)

Front end implementation for currency exchange service.

## Features

- Accepts HTTP connections
- Accepts engine.io connections
- Connects to a ce-operation-hub instance using 0MQ

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

## Roadmap

- Submit JSON operations via REST API
  - Forward operations to ce-operation-hub
  - `POST`
    - `/deposits/[account]/`
    - `/orders/[account]/`
    - `/withdrawals/[account]/`
  - `DELETE`
    - `/orders/[account]/[id]`
- Query order book state via REST API
  - `GET`
    - `/books/[bid-currency]/[offer-currency]/`
- Query delta history via REST API
  - `GET`
    - `/deltas/`
  - Deltas include
    - trades
    - addition, update or removal of orders
  - Deltas should have a sequence ID and this interface should accept a last sequence ID parameter to send deltas after that sequence ID
  - Should be able to specify (default to include nothing)
    - list of bid currencies to include
    - list of order currencies to include
    - include trades
    - include order book changes
- Query account information via REST API
  - `GET`
    - `/balances/[account]/`
    - `/orders/[account]/`
    - `/trades/[account]/`
    - `/withdrawals/[account]/`
    - `/deposits/[account]/`
    - (??) `/operations/[account]/`
- Account creation via REST API
  - `POST`
    - `/accounts/`
- Account updates via REST API
  - `PUT`
    - `/accounts/[account]`
- Authentication
  - local authentication
  - 2 factor authentication (TOTP)
  - admin authenticated
    - `POST`
      - `/deposits/[account]/`
  - user authenticated
    - `POST`
      - `/orders/[account]/`
      - `/withdrawals/[account]/`
    - `DELETE`
      - `/orders/[account]/[id]`
    - `GET`
      - `/balances/[account]/`
      - `/orders/[account]/`
      - `/trades/[account]/`
      - `/withdrawals/[account]/`
      - `/deposits/[account]/`
      - (??) `/operations/[account]/`

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
Copyright (c) 2013 Peter Halliday  
Licensed under the MIT license.
