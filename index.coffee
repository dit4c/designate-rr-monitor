'use strict'

_ = require('lodash')
cli = require('cli')
dns = require('dns')
env = process.env
Hogan = require('hogan.js')
isTcpOn = require('is-tcp-on')
request = require('request')
Q = require('q')

required_envvars = [
  'OS_AUTH_URL',
  'OS_TENANT_NAME',
  'OS_USERNAME',
  'OS_PASSWORD'
]

for v in required_envvars
  if !env[v]
    console.log("Required environment variable "+v+" is not defined.")
    process.exit(1)

newTokenAndEndpoint = (callback) ->
  options =
    url: env.OS_AUTH_URL + 'tokens'
    json: true
    body:
      auth:
        tenantName: env.OS_TENANT_NAME,
        passwordCredentials:
          username: env.OS_USERNAME
          password: env.OS_PASSWORD
  request.post options, (error, response, body) ->
    if (error)
      callback(error)
    else
      token = body.access.token.id
      designateEndpoint = _.chain(body.access.serviceCatalog)
        .filter (obj) -> obj.type == 'dns'
        .pluck 'endpoints'
        .flatten()
        .pluck 'publicURL'
        .head()
        .value()
      callback(null, token, designateEndpoint)

designateRecords = (token, endpoint, recordName, callback) ->
  options =
    url: endpoint + '/domains'
    json: true
    headers:
      'Accept': 'application/json'
      'X-Auth-Token': token
  request.get options, (error, response, body) ->
    if (error)
      callback(error)
    else
      domain = _.find body.domains, (domain) ->
        recordName.indexOf(domain.name) != -1
      options =
        url: endpoint + '/domains/' + domain.id + '/records'
        json: true
        headers:
          'Accept': 'application/json'
          'X-Auth-Token': token
      request.get options, (error, response, body) ->
        records = body.records.filter (r) ->
          r.name == recordName
        callback(null, records)

resolve = (rrtype) -> (hostname) ->
  d = Q.defer()
  dns.resolve hostname, rrtype, (err, result) ->
    d.resolve(if err then [] else result)
  d.promise

# eg. resolveAll('www.google.com', 'www.internode.on.net') ⇒
# { A: [ '150.101.140.197', '216.58.220.100' ],
#   AAAA: [ '2001:44b8:69:2:1::100', '2404:6800:4006:801::2004' ] }
resolveAll = (hostnames) ->
  resolveType = (rrtype) ->
    Q.all(hostnames.map(resolve(rrtype)))
     .then(_.flow(_.flatten, _.sortBy))
  resolveTypes = (types) ->
    Q.all(types.map resolveType)
     .then(_.partial(_.zipObject, types))
  resolveTypes(['A', 'AAAA'])


cli.parse
  'port':     ['p', 'TCP port to check', 'number', 80]
  'servers':  ['s', 'comma-delimited list of servers', 'string']

cli.main (args, options) ->
  recordName = (args[1] || process.exit(1)) + '.'
  servers = (options.servers || process.exit(1)).split(',')
  tcpPort = options.port
  resolveAll(servers).then (obj) ->
    tmpl = Hogan.compile("{{type}}\t{{ip}}\t{{active}}")
    Object.keys(obj).forEach (rrtype) ->
      obj[rrtype].forEach (ip) ->
        r = {ip: ip, type: rrtype}
        isTcpOn({
          port: tcpPort,
          host: r.ip,
        }).then( () ->
          console.log(tmpl.render(_.extend(r, { active: "Up" })))
        , () ->
          console.log(tmpl.render(_.extend(r, { active: "Down" })))
        )
  newTokenAndEndpoint (err, token, endpoint) ->
    designateRecords token, endpoint, recordName, (error, records) ->
      tmpl = Hogan.compile("{{type}}\t{{name}}\t{{data}}\t{{active}}")
      records.filter((r) -> r.type in ['A','AAAA']).forEach (r) ->
        isTcpOn({
          port: tcpPort,
          host: r.data,
        }).then( () ->
          console.log(tmpl.render(_.extend(r, { active: "Up" })))
        , () ->
          console.log(tmpl.render(_.extend(r, { active: "Down" })))
        )
