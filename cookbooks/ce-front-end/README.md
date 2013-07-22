cookbook-ce-front-end
=====================

Chef cookbook to install and start a ce-front-end instance

## Depends

- nodejs
- git
- zeromq (https://github.com/pghalliday/cookbook-zeromq.git)

## Attributes

Attributes are specified under the `ce_front_end` keyspace.

- `node[:ce_front_end][:repository]` - the Git repository to install ce-front-end from (defaults to "https://github.com/pghalliday/ce-front-end.git")
- `node[:ce_front_end][:destination]` - the directory to install ce-front-end to (defaults to "/opt/ce-front-end")
- `node[:ce_front_end][:user]` - the user to install and start ce-front-end as (defaults to "ce-front-end")
- `node[:ce_front_end][:port]` - the port to for the ce-front-end server to listen on (defaults to "3000")
- `node[:ce_front_end][:commission][:account]` - the account ID to apply commission (defaults to "commission")
- `node[:ce_front_end][:ce_operation_hub][:host]` - the host of the ce-operation-hub instance to connect to (defaults to "localhost")
- `node[:ce_front_end][:ce_operation_hub][:submit]` - the port of the ce-operation-hub instance to submit operations to (defaults to "4000")
- `node[:ce_front_end][:ce_delta_hub][:host]` - the host of the ce-delta-hub instance to connect to (defaults to "localhost")
- `node[:ce_front_end][:ce_delta_hub][:stream]` - the port of the ce-delta-hub instance to connect to in order to receive deltas (defaults to "5000")
- `node[:ce_front_end][:ce_delta_hub][:state]` - the port of the ce-delta-hub instance to connect to in order to query the state (defaults to "5001")

## Recipes

### default

- Installs ce-front-end to the given directory
- Runs npm install to get dependencies
- Runs npm start to start the ce-front-end

## License
Copyright &copy; 2013 Peter Halliday  
Licensed under the MIT license.
git ad