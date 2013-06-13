Server = require './Server'
nconf = require 'nconf'

# load configuration
nconf.argv()
config = nconf.get 'config'
if config
  nconf.file
    file: config

server = new Server
  port: nconf.get 'port'
  ceOperationHub:
    host: nconf.get 'ce-operation-hub:host'
    port: nconf.get 'ce-operation-hub:port'
  ceDeltaHub:
    host: nconf.get 'ce-delta-hub:host'
    subscriberPort: nconf.get 'ce-delta-hub:subscriber-port'
    xRequestPort: nconf.get 'ce-delta-hub:xrequest-port'

server.start (error) ->
  if error
    console.log error
  else
    console.log 'ce-front-end started'
    console.log '\tport: ' + nconf.get 'port'
    console.log '\tce-operation-hub:'
    console.log '\t\thost: ' + nconf.get 'ce-operation-hub:host'
    console.log '\t\tport: ' + nconf.get 'ce-operation-hub:port'
    console.log '\tce-delta-hub:'
    console.log '\t\thost: ' + nconf.get 'ce-delta-hub:host'
    console.log '\t\tsubscriber-port: ' + nconf.get 'ce-delta-hub:subscriber-port'
    console.log '\t\txrequest-port: ' + nconf.get 'ce-delta-hub:xrequest-port'
