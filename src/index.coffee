Server = require './Server'
nconf = require 'nconf'

# load configuration
nconf.argv()
config = nconf.get 'config'
if config
  nconf.file
    file: config
port = nconf.get 'port'
ceOperationHub = nconf.get 'ce-operation-hub'

server = new Server
  port: port
  ceOperationHub: ceOperationHub

server.start (error) ->
  if error
    console.log error
  else
    console.log 'ce-front-end started on port ' + port + ' and connecting to ce-operation-hub at ' + ceOperationHub
