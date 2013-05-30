engine = require 'engine.io'
server = engine.listen 3000, ->
  console.log 'ce-front-end started'

# server.on 'connection', (socket) ->
#   socket.send 'utf 8 string'
