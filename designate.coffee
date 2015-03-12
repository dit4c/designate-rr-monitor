'use strict'

_ = require('lodash')
env = process.env
request = require('request')

newTokenAndEndpoint = (callback) ->
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
      token = body.access.token.id
      designateEndpoint = _.chain(body.access.serviceCatalog)
        .filter (obj) -> obj.type == 'dns'
        .pluck 'endpoints'
        .flatten()
        .pluck 'publicURL'
        .head()
        .value()
      callback(null, token, designateEndpoint)

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

module.exports = (recordName) -> (callback) ->
  newTokenAndEndpoint (err, token, endpoint) ->
    designateRecords token, endpoint, recordName, callback
