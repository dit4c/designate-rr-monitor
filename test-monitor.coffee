'use strict'

Monitor = require('./monitor')

fsm = Monitor('localhost', '80')

fsm.onenterup = () ->
  console.log('UP')

fsm.onenterdown = () ->
  console.log('DOWN')

fsm.start()
