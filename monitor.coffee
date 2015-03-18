'use strict'

_ = require('lodash')
Q = require('q')
async = require('async-q')
StateMachine = require('javascript-state-machine')
env = process.env
isTcpOn = require('is-tcp-on')

defaultSettings =
  maxRetry: 5
  interval: 2000

Checker = (settings) ->
  settings = _.defaults(settings, defaultSettings)

  fn = do () ->
    retryCount = 0
    (fsm) ->
      isTcpOn(settings)
        .then () ->
          retryCount = 0
          fsm.online() if fsm.can('online')
        .catch () ->
          if retryCount >= settings.maxRetry
            fsm.offline() if fsm.can('offline')
          else
            retryCount++

  obj = {}
  obj.start = (fsm) ->
    obj._intervalID = setInterval(fn, settings.interval, fsm)
    obj._deferred = Q.defer()
    obj._deferred.promise

  obj.stop = () ->
    clearInterval(obj._intervalID)
    obj._deferred.resolve()

  obj


module.exports = (ipAddr, tcpPort, options) ->
  settings = _.assign {}, options,
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
