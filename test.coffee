'use strict'

expect = require('chai').expect
gutil = require('gulp-util')

out = process.stdout.write.bind(process.stdout)
err = process.stderr.write.bind(process.stderr)

afterEach () ->
  process.stdout.write = out
  process.stderr.write = err

describe 'resolver', () ->
  rslv = require('./resolver')

  it 'is a function', () ->
    expect(rslv).to.be.a('function')

  it 'should handle empty arrays', (done) ->
    rslv([]).done (records) ->
      expect(records).to.be.empty
      done()
