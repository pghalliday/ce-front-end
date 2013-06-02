ce-front-end
============

[![Build Status](https://travis-ci.org/pghalliday/ce-front-end.png?branch=master)](https://travis-ci.org/pghalliday/ce-front-end)
[![Dependency Status](https://gemnasium.com/pghalliday/ce-front-end.png)](https://gemnasium.com/pghalliday/ce-front-end)

Front end implementation for currency exchange service.

## Features

- Accepts HTTP connections
- Accepts engine.io connections
- Connects to a ce-operation-hub instance using 0MQ

## Starting the server

```
$ npm start
```

## Roadmap

- Account creation
- Authentication
  - local authentication
  - 2 factor authentication (TOTP)
- Accept JSON operations using REST API
  - authenticated
  - validated
  - Forward operations to ce-operation-hub
  - POST
    - /[account]/orders/[bid-currency]/[offer-currency]/
    - /[account]/withdrawals/[currency]/
  - DELETE
    - /[account]/orders/[bid-currency]/[offer-currency]/[id]
- Stream trades over engine.io socket
  - send trades with sequence IDs so that a client can detect if any have been missed
  - accept a last known sequence ID parameter and flush trades after that ID to present so that disconnected clients can catch up
  - forward trades from ce-trade-log
  - /trades/[bid-currency]/[offer-currency]/
- Stream order book changes over engine.io socket
  - send order book deltas with sequence IDs so that a client can detect if any have been missed
  - accept a last known sequence ID parameter and flush order book deltas after that ID to present so that disconnected clients can catch up
  - forward order book deltas from ce-order-log
  - /orders/[bid-currency]/[offer-currency]/  
- Query trade history using REST API
  - GET
    - /trades/[bid-currency]/[offer-currency]/
- Query order book state using REST API
  - GET
    - /orders/[bid-currency]/[offer-currency]/
- Query account information using REST API
  - authenticated
  - GET
    - /[account]/balances/[currency]/
    - /[account]/orders/[bid-currency]/[offer-currency]/
    - /[account]/trades/[bid-currency]/[offer-currency]/
    - /[account]/withdrawals/[currency]/
    - /[account]/deposits/[currency]/
    - (??) /[account]/operations/

## Contributing
In lieu of a formal styleguide, take care to maintain the existing coding style. Add unit tests for any new or changed functionality. Lint and test your code using: 

```
$ npm test
```

### Using Vagrant
To use the Vagrantfile you will also need to install the following vagrant plugins

```
$ vagrant plugin install vagrant-omnibus
$ vagrant plugin install vagrant-berkshelf
```

### Workaround for firewalls that block default git:// port
As `engine.io-client` has a dependency on a `git://github.com/` url based module `npm install` will fail if the default port for `git://` urls is blocked by a firewall. These urls can be rewritten to `https://github.com/` with this git configuration change

```
$ git config --global url.https://github.com/.insteadOf git://github.com/
```

## License
Copyright (c) 2013 Peter Halliday  
Licensed under the MIT license.
