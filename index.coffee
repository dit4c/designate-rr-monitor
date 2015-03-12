'use strict'

_ = require('lodash')
Hogan = require('hogan.js')
Q = require('q')
cli = require('cli')
dns = require('dns')
env = process.env
isTcpOn = require('is-tcp-on')
request = require('request')

resolveAll = require('./resolver')

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
