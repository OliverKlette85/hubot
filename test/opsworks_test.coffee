# FIXME webmock
assert   = require("assert")
OpsWorks = require('../lib/opsworks')

describe "OpsWorks", ->
  describe "use", ->
    @timeout(5000)
    it "should initialize with api result", (done) ->
      OpsWorks.use("zeroshiki-stg")
        .then (app) ->
          assert.equal "5ccee25a-3834-4fe9-8753-b61fb9868973", app.StackId
          done()