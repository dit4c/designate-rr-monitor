'use strict'

_ = require('lodash')
Q = require('q')
async = require('async-q')
env = process.env
moment = require('moment')
request = require('request')

newTokenAndEndpoint = (callback) ->
  d = Q.defer()
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
      d.reject(error)
    else
      designateEndpoint = _.chain(body.access.serviceCatalog)
        .filter (obj) -> obj.type == 'dns'
        .pluck 'endpoints'
        .flatten()
        .pluck 'publicURL'
        .head()
        .value()
      d.resolve
        expiry: body.access.token.expires,
        token: body.access.token.id,
        endpoint: designateEndpoint
  d.promise

listDomains = (token, endpoint) ->
  d = Q.defer()
  options =
    url: endpoint + '/domains'
    json: true
    headers:
      'Accept': 'application/json'
      'X-Auth-Token': token
  request.get options, (error, response, body) ->
    if (error)
      d.reject(error)
    else
      d.resolve(body.domains)
  d.promise

listRecords = (token, endpoint, domainId) ->
  d = Q.defer()
  options =
    url: endpoint + '/domains/' + domainId + '/records'
    json: true
    headers:
      'Accept': 'application/json'
      'X-Auth-Token': token
  request.get options, (error, response, body) ->
    if (error)
      d.reject(error)
    else
      d.resolve(body.records)
  d.promise

addRecord = (token, endpoint, domainId, record) ->
  d = Q.defer()
  options =
    url: endpoint + '/domains/' + domainId + '/records'
    json: true
    headers:
      'Accept': 'application/json'
      'X-Auth-Token': token
    body: record
  request.post options, (error, response, body) ->
    if error || response.statusCode != 200
      console.log(error || body)
      d.reject(error)
    else
      d.resolve(body)
  d.promise

deleteRecord = (token, endpoint, domainId, recordId) ->
  d = Q.defer()
  options =
    url: endpoint + '/domains/' + domainId + '/records/' + recordId
    headers:
      'X-Auth-Token': token
  request.del options, (error, response) ->
    if error || response.statusCode != 200
      console.log(error || response.statusCode)
      d.reject(error)
    else
      d.resolve()
  d.promise

factory = (recordName, options) ->
  options ?= {}
  defaultTTL = options.ttl || 60
  expiryBuffer = moment.duration('5', 'minutes')
  infoRef =
    info:
      expiry: '1970-01-01',
      token: null,
      designateUrl: null

  haveCurrentToken = () ->
    moment(infoRef.info.expiry).isAfter(moment().add(expiryBuffer))

  token = () ->
    if haveCurrentToken()
      Q(infoRef.info)
    else
      newTokenAndEndpoint().then (info) ->
        listDomains(info.token, info.endpoint)
          .then (domains) ->
            _.find domains, (d) -> recordName.indexOf(d.name) != -1
          .then (domain) ->
            infoRef.info = _.extend(info, { domain_id: domain.id })

  obj = {}
  obj.list = () ->
    token()
      .then (info) ->
        listRecords(info.token, info.endpoint, info.domain_id)
      .then (records) ->
        _.filter records, (record) ->
          record.name == recordName and record.type in ['A','AAAA']

  add = (type, data) ->
    token().then (info) ->
      addRecord info.token, info.endpoint, info.domain_id,
        name: recordName
        type: type
        data: data
        ttl: defaultTTL

  remove = (record_id) ->
    token().then (info) ->
      deleteRecord info.token, info.endpoint, info.domain_id, record_id

  obj.addAll = (records) ->
    obj.list()
      .then (existingRecords) ->
        recordsToAdd = _.reject records, (r1) ->
          _.some existingRecords, (r2) ->
            r1.type == r2.type && r1.addr == r2.data
        jobs = recordsToAdd.map (r) -> () ->
          add(r.type, r.addr)
        async.series(jobs)
  obj.retainAll = (records) ->
    obj.list()
      .then (existingRecords) ->
        recordsToDelete = _.reject existingRecords, (r1) ->
          _.some records, (r2) ->
            r1.type == r2.type && r1.data == r2.addr
        jobs = recordsToDelete.map (r) -> () ->
          remove(r.id)
        async.series(jobs)
  obj

module.exports = factory
