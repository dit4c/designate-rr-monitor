'use strict'

_ = require('lodash')
Q = require('q')
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
      callback(error)
    else
      designateEndpoint = _.chain(body.access.serviceCatalog)
        .filter (obj) -> obj.type == 'dns'
        .pluck 'endpoints'
        .flatten()
        .pluck 'publicURL'
        .head()
        .value()
      callback null,
        expiry: body.access.token.expires,
        token: body.access.token.id,
        endpoint: designateEndpoint
  d.promise

designateRecords = (token, endpoint, recordName, callback) ->
  options =
    url: endpoint + '/domains'
    json: true
    headers:
      'Accept': 'application/json'
      'X-Auth-Token': token
  request.get options, (error, response, body) ->
    if (error)
      callback(error)
    else
      domain = _.find body.domains, (domain) ->
        recordName.indexOf(domain.name) != -1
      options =
        url: endpoint + '/domains/' + domain.id + '/records'
        json: true
        headers:
          'Accept': 'application/json'
          'X-Auth-Token': token
      request.get options, (error, response, body) ->
        records = body.records.filter (r) ->
          r.name == recordName
        callback(null, records)

Designate = () -> (recordName) ->
  expiryBuffer = moment.duration('5', 'minutes')
  infoRef = {
    info: {
      expiry: '1970-01-01',
      token: null,
      designateUrl: null
    }
  }

  haveCurrentToken = () ->
    moment(infoRef.info.expiry).isAfter(moment().add(expiryBuffer))

  token = () ->
    d = Q.defer()
    if haveCurrentToken()
      d.resolve(info.info)
    else
      newTokenAndEndpoint (err, info) ->
        infoRef.info = info
        d.resolve(infoRef.info)
    d.promise

  d = Q.defer()
  token().then (info) ->
    designateRecords info.token, info.endpoint, recordName, (error, records) ->
      if error then d.reject(error)
      else d.resolve(records)
  d.promise

module.exports = Designate()
