'use strict'

_ = require('lodash')
Hogan = require('hogan.js')
Q = require('q')
async = require('async-q')
braces = require('braces')
cli = require('cli')
env = process.env
gc = require("gc")
isTcpOn = require('is-tcp-on')

getMem = do () ->
  bytes = require('bytes')
  tmpl = Hogan.compile("RSS: {{rss}} ; Heap: {{heapUsed}}/{{heapTotal}}")
  () ->
    mem = _.zipObject(_.map(process.memoryUsage(), (v, k) -> [k, bytes(v)]))
    tmpl.render(mem)

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

cli.enable('status').setUsage("designate-rr-monitor [OPTIONS] <record>")

cli.parse
  'delete':   ['d', 'Delete all records', 'boolean']
  'port':     ['p', 'TCP port to check', 'number', 80]
  'servers':  ['s',
    'whitespace-delimited list of servers (which may use brace expansion)',
    'string']
  'watch':    ['w', 'Monitor for changes after first check', 'boolean']

cli.main (args, options) ->
  recordName =
    if _.isEmpty(args)
      cli.fatal("Record name must be specified!")
    else
      args.pop().trim('.')+ '.'
  servers = _.flatten((options.servers ? '').split(/\s+/).map(braces))
  tcpPort = options.port

  if options.watch and options['delete']
    cli.fatal("Deletion is a once-only operation.")

  if _.isEmpty(options.servers) and !options['delete']
    cli.fatal("Must specify servers unless deleting all records.")


  designate = require('./designate')(recordName)

  monitors = []

  recordsAreSame = (r1, r2) ->
    r1.type == r2.type and r1.addr == r2.addr

  sitrep = do () ->
    emptyTmpl = Hogan.compile(
      "{{name}} {{whenchecked}} has no records.")
    recordsTmpl = Hogan.compile(
      "{{name}} {{type}} records {{whenchecked}}:\t{{#addrs}} {{.}}{{/addrs}}")
    (whenChecked) -> (currentRecords) ->
      if _.isEmpty(currentRecords)
        cli.debug emptyTmpl.render
          name: _.trim(recordName, '.')
          whenchecked: whenChecked
      else
        grouped = _.groupBy(currentRecords, 'type')
        Object.keys(grouped).forEach (type) ->
          cli.debug recordsTmpl.render
            name: _.trim(recordName, '.')
            whenchecked: whenChecked
            type: type
            addrs: _.pluck(grouped[type], "data")
      currentRecords

  updateDesignateRecords = do () ->
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
    queuedFn = () ->
      executing = null
      semaphoredFn = () ->
        Q.try(() -> executing = fn()).then(() -> executing = null)
      if executing
        executing.then semaphoredFn
      else
        executing = semaphoredFn()
    _.throttle(queuedFn, 1000, leading: false)

  resolveAndUpdateMonitors = () ->
    resolveAll(servers)
      .then (records) ->
        Q()
          .then () ->
            _.reject records, (record) ->
              _.some(monitors, _.partial(recordsAreSame, record))
          .then (recordsWithoutMonitors) ->
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
                null
              .then () ->
                records
      .then (records) ->
        Q()
          .then () ->
            _.reject monitors, (monitor) ->
              _.some(records, _.partial(recordsAreSame, monitor))
          .then (monitorsWithoutRecords) ->
            if _.isEmpty(monitorsWithoutRecords)
              records
            else
              Q.all monitorsWithoutRecords.map (m) ->
                m.monitor.stop()
                m.monitor = null
              .then () ->
                monitors = monitors.reject (m) ->
                  _.some(monitorsWithoutRecords, _.partial(recordsAreSame, m))
                records

  if options.watch
    async.forever () ->
      resolveAndUpdateMonitors()
        .then () ->
          cli.debug(getMem())
          gc() # Garbage collecting here "fixes" the memory leak!
          Q.delay(60000)
  else if options['delete']
    updateDesignateRecords()
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
