Server = require './Server'

server = new Server
  port: 3000

server.start (error) ->
  if (error)
    console.log error
  else
    console.log 'ce-front-end started'
