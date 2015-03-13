'use strict'

_ = require('lodash')
Hogan = require('hogan.js')
Q = require('q')
async = require('async-q')
braces = require('braces')
cli = require('cli')
env = process.env
isTcpOn = require('is-tcp-on')

Monitor = require('./monitor')
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
  'watch':    ['w', 'Monitor for changes after first check', 'boolean']
  'port':     ['p', 'TCP port to check', 'number', 80]
  'servers':  ['s', 'whitespace-delimited list of servers (which may use brace expansion)', 'string']

cli.main (args, options) ->
  recordName = (args[1] || process.exit(1)) + '.'
  servers = _.flatten((options.servers || []).split(/\s+/).map(braces))
  tcpPort = options.port

  designate = require('./designate')(recordName)

  monitors = []

  recordsAreSame = (r1, r2) ->
    r1.type == r2.type and r1.addr == r2.addr

  updateDesignateRecords = do () ->
    executing = null
    sitrepTmpl = Hogan.compile(
      "{{name}} {{type}} records {{whenchecked}}:\t{{#addrs}} {{.}}{{/addrs}}")
    sitrep = (whenChecked) -> (currentRecords) ->
      grouped = _.groupBy(currentRecords, 'type')
      Object.keys(grouped).forEach (type) ->
        cli.debug sitrepTmpl.render
          name: _.trim(recordName, '.')
          type: type
          whenchecked: whenChecked
          addrs: _.pluck(grouped[type], "data")
      currentRecords
    fn = () ->
      designate.list()
        .then sitrep("pre-update")
        .then () ->
          designate.addAll(monitors.filter (m) -> m.monitor.is('up'))
        .then () ->
          designate.retainAll(monitors.filter (m) -> !m.monitor.is('down'))
        .then () ->
          designate.list()
        .then sitrep("post-update")
    semaphoredFn = () ->
      Q.try(() -> executing = fn()).then(() -> executing = null)
    queuedFn = () ->
      if executing
        executing.then semaphoredFn
      else
        executing = semaphoredFn()
    _.throttle(queuedFn, 1000, leading: false)

  resolveAndUpdateMonitors = () ->
    resolveAll(servers)
      .then (records) ->
        recordsWithoutMonitors = _.reject records, (record) ->
          _.some(monitors, _.partial(recordsAreSame, record))

        if _.isEmpty(recordsWithoutMonitors)
          records
        else
          Q.all recordsWithoutMonitors.map (r) ->
              monitor = Monitor(r.addr, tcpPort)
              monitor.onenterup = () ->
                cli.info(r.addr+" is up")
                updateDesignateRecords()
              monitor.onenterdown = () ->
                cli.info(r.addr+" is down")
                updateDesignateRecords()
              monitors.push(_.extend(r, { monitor: monitor }))
              monitor.start()
            .then () ->
              records
      .then (records) ->
        monitorsWithoutRecords = _.reject monitors, (monitor) ->
          _.some(records, _.partial(recordsAreSame, monitor))

        if _.isEmpty(monitorsWithoutRecords)
          records
        else
          Q.all monitorsWithoutRecords.map (m) ->
              m.stop()
              m
            .then () ->
              monitors = monitors.reject (m) ->
                _.some(monitorsWithoutRecords, _.partial(recordsAreSame, m))
            .then () ->
              records

  if options.watch
    async.forever () ->
      resolveAndUpdateMonitors()
        .then () ->
          Q.delay(60000)
  else
    cli.debug("Resolving once only. Use -w to monitor indefinitely.")
    finished = () ->
      _.all(monitors, (m) -> !m.monitor.is('unknown'))
    resolveAndUpdateMonitors()
      .then () ->
        async.until(finished, () -> Q.delay(500))
      .then () ->
        if _.isEmpty(monitors)
          Q()
        else
          Q.all monitors.map (m) ->
            m.monitor.stop()
      .done()
