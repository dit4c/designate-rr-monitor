'use strict'

_ = require('lodash')
Q = require('q')
async = require('async-q')
StateMachine = require('javascript-state-machine')
env = process.env
isTcpOn = require('is-tcp-on')

maxRetry = 5
interval = 2000

Checker = (settings) ->
  cancelled = false

  obj = {}
  obj.start = (fsm) ->
    retryCount = 0
    test = () ->
      cancelled
    fn = () ->
      d = Q.defer()
      success = () ->
        retryCount = 0
        fsm.online() if fsm.can('online')
        d.resolve()
      failure = () ->
        if retryCount >= maxRetry
          fsm.offline() if fsm.can('offline')
        else
          retryCount++
        d.resolve()
      isTcpOn(settings).then(success, failure)
      d.promise.then () ->
        Q.delay(interval)
    obj._promise = async.until(test, fn)

  obj.stop = () ->
    cancelled = true
    obj._promise

  obj


module.exports = (ipAddr, tcpPort) ->
  settings =
    host: ipAddr
    port: tcpPort

  fsm = StateMachine.create
    initial: 'inactive',
    events: [
      { name: 'start',    from: 'inactive',                 to: 'unknown' },
      { name: 'stop',     from: ['up', 'down', 'unknown'],  to: 'inactive'},
      { name: 'offline',  from: ['up', 'unknown'],          to: 'down' },
      { name: 'online',   from: ['down', 'unknown'],        to: 'up'  }
    ]

  checker = Checker(settings)
  fsm.onstart = () -> checker.start(fsm)
  fsm.onstop  = () -> checker.stop()

  fsm
