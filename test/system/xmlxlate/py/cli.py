

import xmlrpclib
import sys

server_url = "http://0.0.0.0:8081/xlater"
server = xmlrpclib.Server (server_url)
server.system.setDebugLevel (50)

res = server.xdr.xlate (
    { "hostname" : "127.0.0.1",
      "port" : 4000,
      "program" : "tst_prog_1",
      "procno" : 2,
      "arg" : { "xx" : 1,
                "a" : { "x" : 40,
                        "y" : "foobarbar"}}
      } )


print (res)

res = server.xdr.xlate (
    { "hostname" : "127.0.0.1",
      "port" : 4000,
      "program" : "tst_prog_1",
      "procno" : 1,
      "arg" : { "x" : 40,
                "y" : "footimetime"}
      } )

print (res)