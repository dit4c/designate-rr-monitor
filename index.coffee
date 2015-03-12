'use strict'

_ = require('lodash')
Hogan = require('hogan.js')
Q = require('q')
cli = require('cli')
env = process.env
isTcpOn = require('is-tcp-on')

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
  require('./designate')(recordName)
    .done (records) ->
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
