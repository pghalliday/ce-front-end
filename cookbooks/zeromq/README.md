zeromq cookbook
===============

Chef cookbook to install 0MQ.

## Depends

- build-essential

## Attributes

Attributes are specified under the `zeromq` keyspace.

- `node[:zeromq][:version]` - the version to install (defaults to "3.2.3")
- `node[:zeromq][:url]` - the url (defaults to "http://download.zeromq.org")

## Recipes

### default

Installs 0MQ at the required version

## License
Copyright (c) 2013 Peter Halliday  
Licensed under the MIT license.
