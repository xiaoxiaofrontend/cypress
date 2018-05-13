_ = require("lodash")
bodyParser = require("body-parser")
jsonSchemas = require("@cypress/json-schemas").api
e2e = require("../support/helpers/e2e")

postRunResponse = jsonSchemas.getExample("postRunResponse")("2.0.0")
postRunInstanceResponse = jsonSchemas.getExample("postRunInstanceResponse")("2.0.0")

{ runId, planId, machineId } = postRunResponse
{ instanceId } = postRunInstanceResponse

requests = null

getRequestUrls = ->
  _.map(requests, "url")

getSchemaErr = (err, schema) ->
  {
    errors: err.errors
    object: err.object
    example: err.example
    message: "Request should follow #{schema} schema"
  }

getResponse = (responseSchema) ->
  if _.isObject(responseSchema)
    return responseSchema

  [ name, version ] = responseSchema.split("@")

  jsonSchemas.getExample(name)(version)

sendResponse = (res, responseSchema) ->
  if _.isFunction(responseSchema)
    return responseSchema(res)

  res.json(getResponse(responseSchema))

ensureSchema = (requestSchema, responseSchema) ->
  [ name, version ] = requestSchema.split("@")

  return (req, res) ->
    { body } = req

    try
      jsonSchemas.assertSchema(name, version)(body)
      sendResponse(res, responseSchema)

      key = [req.method, req.url].join(" ")

      requests.push({
        url: key
        body
      })
    catch err
      res.status(400).json(getSchemaErr(err, requestSchema))

onServer = (routes) ->
  return (app) ->
    app.use(bodyParser.json())

    _.each routes, (route) ->
      app[route.method](route.url, ensureSchema(
        route.req,
        route.res
      ))

setup = (routes) ->
  e2e.setup({
    settings: {
      projectId: "pid123"
    }
    servers: {
      port: 1234
      onServer: onServer(routes)
    }
  })

describe "e2e record", ->
  beforeEach ->
    requests = []

  context "passing", ->
    routes = [
      {
        method: "post"
        url: "/runs"
        req: "postRunRequest@2.0.0",
        res: postRunResponse
      }, {
        method: "post"
        url: "/runs/:id/instances"
        req: "postRunInstanceRequest@2.0.0",
        res: postRunInstanceResponse
      }, {
        method: "put"
        url: "/instances/:id"
        req: "putInstanceRequest@2.0.0",
        res: "putInstanceResponse@2.0.0"
      }, {
        method: "put"
        url: "/instances/:id/stdout"
        req: "putInstanceStdoutRequest@1.0.0",
        res: (res) -> res.sendStatus(200)
      }
    ]

    setup(routes)

    it "passes", ->
      e2e.exec(@, {
        key: "f858a2bc-b469-4e48-be67-0876339ee7e1"
        spec: "record*"
        record: true
        snapshot: true
        expectedExitCode: 3
      })
      .then ->
        urls = getRequestUrls()

        expect(urls).to.deep.eq([
          "POST /runs"
          "POST /runs/#{runId}/instances"
          "PUT /instances/#{instanceId}"
          "PUT /instances/#{instanceId}/stdout"
          "POST /runs/#{runId}/instances"
          "PUT /instances/#{instanceId}"
          "PUT /instances/#{instanceId}/stdout"
          "POST /runs/#{runId}/instances"
          "PUT /instances/#{instanceId}"
          "PUT /instances/#{instanceId}/stdout"
          "POST /runs/#{runId}/instances"
          "PUT /instances/#{instanceId}"
          "PUT /instances/#{instanceId}/stdout"
        ])

        postRun = requests[0]

        ## ensure its relative to projectRoot
        expect(postRun.body.specs).to.deep.eq([
          "cypress/integration/record_error_spec.coffee"
          "cypress/integration/record_fail_spec.coffee"
          "cypress/integration/record_pass_spec.coffee"
          "cypress/integration/record_uncaught_spec.coffee"
        ])
        expect(postRun.body.projectId).to.eq("pid123")
        expect(postRun.body.recordKey).to.eq("f858a2bc-b469-4e48-be67-0876339ee7e1")
        expect(postRun.body.specPattern).to.eq("cypress/integration/record*")

        firstInstance = requests[1]
        expect(firstInstance.body.planId).to.eq(planId)
        expect(firstInstance.body.machineId).to.eq(machineId)
        expect(firstInstance.body.spec).to.eq(
          "cypress/integration/record_error_spec.coffee"
        )

        firstInstancePut = requests[2]
        expect(firstInstancePut.body.error).to.include("Oops...we found an error preparing this test file")
        expect(firstInstancePut.body.tests).to.be.null
        expect(firstInstancePut.body.hooks).to.be.null
        expect(firstInstancePut.body.screenshots).to.have.length(0)
        expect(firstInstancePut.body.stats.tests).to.eq(0)
        expect(firstInstancePut.body.stats.failures).to.eq(1)
        expect(firstInstancePut.body.stats.passes).to.eq(0)

        firstInstanceStdout = requests[3]
        expect(firstInstanceStdout.body.stdout).to.include("record_error_spec.coffee")

        secondInstance = requests[4]
        expect(secondInstance.body.planId).to.eq(planId)
        expect(secondInstance.body.machineId).to.eq(machineId)
        expect(secondInstance.body.spec).to.eq(
          "cypress/integration/record_fail_spec.coffee"
        )

        secondInstancePut = requests[5]
        expect(secondInstancePut.body.error).to.be.null
        expect(secondInstancePut.body.tests).to.have.length(2)
        expect(secondInstancePut.body.hooks).to.have.length(1)
        expect(secondInstancePut.body.screenshots).to.have.length(1)
        expect(secondInstancePut.body.stats.tests).to.eq(2)
        expect(secondInstancePut.body.stats.failures).to.eq(1)
        expect(secondInstancePut.body.stats.passes).to.eq(0)
        expect(secondInstancePut.body.stats.skipped).to.eq(1)

        secondInstanceStdout = requests[6]
        expect(secondInstanceStdout.body.stdout).to.include("record_fail_spec.coffee")
        expect(secondInstanceStdout.body.stdout).not.to.include("record_error_spec.coffee")

        thirdInstance = requests[7]
        expect(thirdInstance.body.planId).to.eq(planId)
        expect(thirdInstance.body.machineId).to.eq(machineId)
        expect(thirdInstance.body.spec).to.eq(
          "cypress/integration/record_pass_spec.coffee"
        )

        thirdInstancePut = requests[8]
        expect(thirdInstancePut.body.error).to.be.null
        expect(thirdInstancePut.body.tests).to.have.length(2)
        expect(thirdInstancePut.body.hooks).to.have.length(0)
        expect(thirdInstancePut.body.screenshots).to.have.length(1)
        expect(thirdInstancePut.body.stats.tests).to.eq(2)
        expect(thirdInstancePut.body.stats.passes).to.eq(1)
        expect(thirdInstancePut.body.stats.failures).to.eq(0)
        expect(thirdInstancePut.body.stats.pending).to.eq(1)

        thirdInstanceStdout = requests[9]
        expect(thirdInstanceStdout.body.stdout).to.include("record_pass_spec.coffee")
        expect(thirdInstanceStdout.body.stdout).not.to.include("record_error_spec.coffee")
        expect(thirdInstanceStdout.body.stdout).not.to.include("record_fail_spec.coffee")

        fourthInstance = requests[10]
        expect(fourthInstance.body.planId).to.eq(planId)
        expect(fourthInstance.body.machineId).to.eq(machineId)
        expect(fourthInstance.body.spec).to.eq(
          "cypress/integration/record_uncaught_spec.coffee"
        )

        fourthInstancePut = requests[11]
        expect(fourthInstancePut.body.error).to.be.null
        expect(fourthInstancePut.body.tests).to.have.length(1)
        expect(fourthInstancePut.body.hooks).to.have.length(0)
        expect(fourthInstancePut.body.screenshots).to.have.length(1)
        expect(fourthInstancePut.body.stats.tests).to.eq(1)
        expect(fourthInstancePut.body.stats.failures).to.eq(1)
        expect(fourthInstancePut.body.stats.passes).to.eq(0)

        forthInstanceStdout = requests[12]
        expect(forthInstanceStdout.body.stdout).to.include("record_uncaught_spec.coffee")
        expect(forthInstanceStdout.body.stdout).not.to.include("record_error_spec.coffee")
        expect(forthInstanceStdout.body.stdout).not.to.include("record_fail_spec.coffee")
        expect(forthInstanceStdout.body.stdout).not.to.include("record_pass_spec.coffee")

  context "api interaction errors", ->
    describe "recordKey and projectId", ->
      routes = [
        {
          method: "post"
          url: "/runs"
          req: "postRunRequest@2.0.0",
          res: (res) -> res.sendStatus(401)
        }
      ]

      setup(routes)

      it "errors and exits", ->
        e2e.exec(@, {
          key: "f858a2bc-b469-4e48-be67-0876339ee7e1"
          spec: "record_pass*"
          record: true
          snapshot: true
          expectedExitCode: 1
        })

    describe "project 404", ->
      routes = [
        {
          method: "post"
          url: "/runs"
          req: "postRunRequest@2.0.0",
          res: (res) -> res.sendStatus(404)
        }
      ]

      setup(routes)

      it "errors and exits", ->
        e2e.exec(@, {
          key: "f858a2bc-b469-4e48-be67-0876339ee7e1"
          spec: "record_pass*"
          record: true
          snapshot: true
          expectedExitCode: 1
        })

    describe "create run", ->
      routes = [{
        method: "post"
        url: "/runs"
        req: "postRunRequest@2.0.0",
        res: (res) -> res.sendStatus(500)
      }]

      setup(routes)

      it "warns and does not create or update instances", ->
        e2e.exec(@, {
          key: "f858a2bc-b469-4e48-be67-0876339ee7e1"
          spec: "record_pass*"
          record: true
          snapshot: true
          expectedExitCode: 0
        })
        .then ->
          urls = getRequestUrls()

          expect(urls).to.deep.eq([
            "POST /runs"
          ])

    describe "create instance", ->
      routes = [
        {
          method: "post"
          url: "/runs"
          req: "postRunRequest@2.0.0",
          res: postRunResponse
        }, {
          method: "post"
          url: "/runs/:id/instances"
          req: "postRunInstanceRequest@2.0.0",
          res: (res) -> res.sendStatus(500)
        }
      ]

      setup(routes)

      it "does not update instance", ->
        e2e.exec(@, {
          key: "f858a2bc-b469-4e48-be67-0876339ee7e1"
          spec: "record_pass*"
          record: true
          snapshot: true
          expectedExitCode: 0
        })
        .then ->
          urls = getRequestUrls()

          expect(urls).to.deep.eq([
            "POST /runs"
            "POST /runs/#{runId}/instances"
          ])

    describe "update instance", ->
      routes = [
        {
          method: "post"
          url: "/runs"
          req: "postRunRequest@2.0.0",
          res: postRunResponse
        }, {
          method: "post"
          url: "/runs/:id/instances"
          req: "postRunInstanceRequest@2.0.0",
          res: postRunInstanceResponse
        }, {
          method: "put"
          url: "/instances/:id"
          req: "putInstanceRequest@2.0.0",
          res: (res) -> res.sendStatus(500)
        }
      ]

      setup(routes)

      it "does not update instance stdout", ->
        e2e.exec(@, {
          key: "f858a2bc-b469-4e48-be67-0876339ee7e1"
          spec: "record_pass*"
          record: true
          snapshot: true
          expectedExitCode: 0
        })
        .then ->
          urls = getRequestUrls()

          expect(urls).to.deep.eq([
            "POST /runs"
            "POST /runs/#{runId}/instances"
            "PUT /instances/#{instanceId}"
          ])

    describe "update instance stdout", ->
      routes = [
        {
          method: "post"
          url: "/runs"
          req: "postRunRequest@2.0.0",
          res: postRunResponse
        }, {
          method: "post"
          url: "/runs/:id/instances"
          req: "postRunInstanceRequest@2.0.0",
          res: postRunInstanceResponse
        }, {
          method: "put"
          url: "/instances/:id"
          req: "putInstanceRequest@2.0.0",
          res: "putInstanceResponse@2.0.0"
        }, {
          method: "put"
          url: "/instances/:id/stdout"
          req: "putInstanceStdoutRequest@1.0.0",
          res: (res) -> res.sendStatus(500)
        }
      ]

      setup(routes)

      it "warns but proceeds", ->
        e2e.exec(@, {
          key: "f858a2bc-b469-4e48-be67-0876339ee7e1"
          spec: "record_pass*"
          record: true
          snapshot: true
          expectedExitCode: 0
        })
        .then ->
          urls = getRequestUrls()

          expect(urls).to.deep.eq([
            "POST /runs"
            "POST /runs/#{runId}/instances"
            "PUT /instances/#{instanceId}"
            "PUT /instances/#{instanceId}/stdout"
          ])
