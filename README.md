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

- Submit JSON operations via REST API
  - Forward operations to ce-operation-hub
  - `POST`
    - `/accounts/[account]/orders/[bid-currency]/[offer-currency]/`
    - `/accounts/[account]/withdrawals/[currency]/`
  - `DELETE`
    - `/accounts/[account]/orders/[bid-currency]/[offer-currency]/[id]`
- Query order book state via REST API
  - `GET`
    - `/orders/[bid-currency]/[offer-currency]/`
- Query trade history via REST API
  - `GET`
    - `/trades/[bid-currency]/[offer-currency]/`
- Query order book deltas via REST API
  - `GET`
    - `/deltas/[bid-currency]/[offer-currency]/`
- Stream trades over engine.io socket
  - send trades with sequence IDs so that a client can detect if any have been missed
  - accept a last known sequence ID parameter and flush trades after that ID to present so that disconnected clients can catch up
  - forward trades from ce-trade-log
  - `/trades/[bid-currency]/[offer-currency]/`
- Stream order book changes over engine.io socket
  - send order book deltas with sequence IDs so that a client can detect if any have been missed
  - accept a last known sequence ID parameter and flush order book deltas after that ID to present so that disconnected clients can catch up
  - forward order book deltas from ce-order-log
  - `/deltas/[bid-currency]/[offer-currency]/` 
- Query account information via REST API
  - `GET`
    - `/accounts/[account]/balances/[currency]/`
    - `/accounts/[account]/orders/[bid-currency]/[offer-currency]/`
    - `/accounts/[account]/trades/[bid-currency]/[offer-currency]/`
    - `/accounts/[account]/withdrawals/[currency]/`
    - `/accounts/[account]/deposits/[currency]/`
    - (??) `/accounts/[account]/operations/`
- Account creation via REST API
  - `POST`
    - `/accounts/`
- Account updates via REST API
  - `PUT`
    - `/accounts/[account]`
- Authentication
  - local authentication
  - 2 factor authentication (TOTP)
  - Authenticate `/accounts/[account]/` interfaces

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
