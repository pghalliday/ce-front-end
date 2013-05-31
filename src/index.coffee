Server = require './Server'

server = new Server
  port: 3000
  ceOperationHub: 'tcp://127.0.0.1:3001'

server.start (error) ->
  if (error)
    console.log error
  else
    console.log 'ce-front-end started'
