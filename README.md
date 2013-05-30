ce-front-end
============

Front end implementation for currency exchange service.

# Starting the server

```
$ npm start
```

## Roadmap

- Accept websocket connections?
  - engine.io?
- Implement web page to connect to websocket interface
- Accept JSON operations
- Submit JSON operations to ce-operation-log 
- Report success or failure of JSON operations
- Account creation
- Authentication
- Query order books
- Stream trades
- Stream order book changes
- Query balances
- Query operation history
- Query trade history

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

## License
Copyright (c) 2013 Peter Halliday  
Licensed under the MIT license.
