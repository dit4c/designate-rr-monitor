'use strict'

_ = require('lodash')
Q = require('q')
dns = require('dns')

resolve = (rrtype) -> (hostname) ->
  d = Q.defer()
  dns.resolve hostname, rrtype, (err, result) ->
    d.resolve(if err then [] else result)
  d.promise

# eg. resolveAll('www.google.com', 'www.internode.on.net') ⇒
# { A: [ '150.101.140.197', '216.58.220.100' ],
#   AAAA: [ '2001:44b8:69:2:1::100', '2404:6800:4006:801::2004' ] }
module.exports = (hostnames) ->
  resolveType = (rrtype) ->
    Q.all(hostnames.map(resolve(rrtype)))
     .then(_.flow(_.flatten, _.sortBy))
  resolveTypes = (types) ->
    Q.all(types.map(resolveType))
     .then(_.partial(_.zipObject, types))
  resolveTypes(['A', 'AAAA'])
