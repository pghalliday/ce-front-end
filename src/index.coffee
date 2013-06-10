Server = require './Server'
nconf = require 'nconf'

# load configuration
nconf.argv()
config = nconf.get 'config'
if config
  nconf.file
    file: config
port = nconf.get 'port'

server = new Server
  port: port
  ceOperationHub: 'tcp://127.0.0.1:3001'

server.start (error) ->
  if error
    console.log error
  else
    console.log 'ce-front-end started on port ' + port
