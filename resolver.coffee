'use strict'

_ = require('lodash')
Q = require('q')
dns = require('dns')

class DnsRecord
  constructor: (@type, @addr) ->
    # Nothing required

resolve = (rrtype) -> (hostname) ->
  d = Q.defer()
  dns.resolve hostname, rrtype, (err, result) ->
    d.resolve(if err then [] else result)
  d.promise

eqVal = (r) ->
  r.type+"!"+r.addr

# eg. resolveAll('www.google.com', 'www.internode.on.net') ⇒
# [
#   { type: 'A', addr: '150.101.140.197' }
#   { type: 'A', addr: '216.58.220.100' }
#   { type: 'AAAA', addr: '2001:44b8:69:2:1::100' }
#   { type: 'AAAA', addr: '2404:6800:4006:801::2004' }
# ]
module.exports = (hostnames) ->
  resolveType = (rrtype) ->
    Q.all(hostnames.map(resolve(rrtype)))
      .then _.flow(_.flatten, _.sortBy)
      .then (addrs) ->
        addrs.map (addr) -> new DnsRecord(rrtype, addr)
  resolveTypes = (types) ->
    Q.all(types.map(resolveType))
      .then _.flow(_.flatten, (l) -> _.uniq(l, false, eqVal))
  resolveTypes(['A', 'AAAA'])
