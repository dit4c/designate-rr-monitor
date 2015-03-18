'use strict'

_ = require('lodash')
Hogan = require('hogan.js')
Q = require('q')
async = require('async-q')
expect = require('chai').expect
gutil = require('gulp-util')
memwatch = require('memwatch')

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

  it 'should handle resolve IPv4 & IPv6 addresses', (done) ->
    this.slow(200)
    rslv(['www.google.com']).done (records) ->
      expect(records.filter (r) -> r.type == 'A').not.to.be.empty
      expect(records.filter (r) -> r.type == 'AAAA').not.to.be.empty
      done()

describe 'monitor', () ->
  Monitor = require('./monitor')

  getMem = do () ->
    bytes = require('bytes')
    tmpl = Hogan.compile("RSS: {{rss}} ; Heap: {{heapUsed}}/{{heapTotal}}")
    () ->
      mem = _.zipObject(_.map(process.memoryUsage(), (v, k) -> [k, bytes(v)]))
      tmpl.render(mem)

  it 'should not leak memory', (done) ->
    this.timeout(15000)
    this.slow(12000)
    monitor = Monitor '127.0.0.1', 1234,
      interval: 1

    monitor.start()

    hd = null

    Q.delay(100)
      .then () ->
        hd = new memwatch.HeapDiff()

    Q.delay(5000)
      .then () ->
        diff = hd.end()
        monitor.stop()
        diff
      .done (diff) ->
        # Should not vary by more than 10%
        expect(diff.change.size_bytes)
          .to.be.lessThan(Math.floor(diff.before.size_bytes*0.1))
        done()
