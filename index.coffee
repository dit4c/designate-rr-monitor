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

  designate = require('./designate')(recordName)

  resolveAll(servers)
    .then (records) ->
      Q.all records.map (r) ->
        d = Q.defer()
        isTcpOn({
          port: tcpPort,
          host: r.addr,
        }).then( () ->
          d.resolve(_.extend(r, { active: true }))
        , () ->
          d.resolve(_.extend(r, { active: false }))
        )
        d.promise
    .then (records) ->
      tmpl = Hogan.compile("{{name}}\t{{type}}\t{{ttl}}\t{{data}}")
      designate.list()
        .then (currentRecords) ->
          console.log("Before:")
          currentRecords.forEach (r) ->
            console.log(tmpl.render(r))
        .then () ->
          designate.addAll(records.filter (r) -> r.active)
        .then () ->
          designate.retainAll(records.filter (r) -> r.active != false)
        .then () ->
          designate.list()
        .then (currentRecords) ->
          console.log("After:")
          currentRecords.forEach (r) ->
            console.log(tmpl.render(r))
    .done()
