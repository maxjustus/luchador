local msgpack = require 'MessagePack'
Seralizer = {}

function Seralizer.serialize(string)
  return msgpack.pack(string)
end

function Seralizer.deserialize(string)
  return msgpack.unpack(string)
end

return Seralizer
