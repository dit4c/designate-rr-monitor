env = process.env
Hogan = require('hogan.js')
isTcpOn = require('is-tcp-on')
request = require('request')
_ = require('lodash')

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
          r.name == recordName && r.type in ['A','AAAA']
        callback(null, records)

recordName = (process.argv[2] || process.exit(1)) + '.'
tcpPort = (process.argv[3] || 80) + '.'

newTokenAndEndpoint (err, token, endpoint) ->
  designateRecords token, endpoint, recordName, (error, records) ->
    tmpl = Hogan.compile("{{id}}\t{{name}}\t{{data}}\t{{active}}")
    records.forEach (r) ->
      isTcpOn({
          port: tcpPort,
          host: r.data,
      }).then( () ->
        console.log(tmpl.render(_.extend(r, { active: "Up" })))
      , () ->
        console.log(tmpl.render(_.extend(r, { active: "Down" })))
      )
