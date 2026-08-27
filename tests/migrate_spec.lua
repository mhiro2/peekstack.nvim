local migrate = require("peekstack.persist.migrate")

describe("migrate", function()
  describe("ensure", function()
    it("returns default for nil input", function()
      local result = migrate.ensure(nil)
      assert.equals(2, result.version)
      assert.same({}, result.sessions)
    end)

    it("returns default for non-table input", function()
      assert.same({ version = 2, sessions = {} }, migrate.ensure("string"))
      assert.same({ version = 2, sessions = {} }, migrate.ensure(42))
      assert.same({ version = 2, sessions = {} }, migrate.ensure(true))
    end)

    it("migrates version 1 data to version 2", function()
      local data = { version = 1, items = { { uri = "file:///tmp/a.lua" } } }
      local result = migrate.ensure(data)
      assert.equals(2, result.version)
      assert.is_not_nil(result.sessions.default)
      assert.equals(1, #result.sessions.default.items)
      assert.equals("file:///tmp/a.lua", result.sessions.default.items[1].uri)
    end)

    it("returns data as-is for valid version 2 data", function()
      local data = {
        version = 2,
        sessions = {
          test = {
            items = { { uri = "file:///tmp/b.lua" } },
            meta = { created_at = 123, updated_at = 456 },
          },
        },
      }
      local result = migrate.ensure(data)
      assert.equals(2, result.version)
      assert.is_not_nil(result.sessions.test)
      assert.equals(1, #result.sessions.test.items)
      assert.equals("file:///tmp/b.lua", result.sessions.test.items[1].uri)
    end)

    it("returns default for missing version", function()
      local result = migrate.ensure({ sessions = {} })
      assert.equals(2, result.version)
      assert.same({}, result.sessions)
    end)

    it("returns default for wrong version number", function()
      local result = migrate.ensure({ version = 3, sessions = {} })
      assert.equals(2, result.version)
      assert.same({}, result.sessions)
    end)

    it("returns data with empty sessions table", function()
      local data = { version = 2, sessions = {} }
      local result = migrate.ensure(data)
      assert.equals(2, result.version)
      assert.same({}, result.sessions)
    end)

    it("handles missing sessions in version 2 data", function()
      local result = migrate.ensure({ version = 2 })
      assert.equals(2, result.version)
      assert.same({}, result.sessions)
    end)

    it("drops non-table session entries in version 2 data", function()
      local result = migrate.ensure({
        version = 2,
        sessions = {
          bad = true,
          worse = "nope",
          good = { items = {}, meta = { created_at = 1, updated_at = 2 } },
        },
      })
      assert.is_nil(result.sessions.bad)
      assert.is_nil(result.sessions.worse)
      assert.same({ items = {}, meta = { created_at = 1, updated_at = 2 } }, result.sessions.good)
    end)

    it("normalizes malformed items and meta in version 2 sessions", function()
      local result = migrate.ensure({
        version = 2,
        sessions = {
          no_items = { meta = { created_at = 10, updated_at = 20 } },
          string_items = { items = "x", meta = { created_at = 10 } },
          no_meta = { items = { { uri = "file:///tmp/c.lua" } } },
          bad_meta = { items = {}, meta = "bad" },
          dict_items = { items = { a = { uri = "file:///tmp/d.lua" } }, meta = { created_at = 1, updated_at = 1 } },
          list_meta = { items = {}, meta = { 1, 2 } },
        },
      })

      assert.same({}, result.sessions.dict_items.items)
      assert.equals("number", type(result.sessions.list_meta.meta.created_at))
      assert.is_nil(result.sessions.list_meta.meta[1])

      assert.same({}, result.sessions.no_items.items)
      assert.same({}, result.sessions.string_items.items)
      assert.equals(10, result.sessions.string_items.meta.created_at)
      assert.equals(10, result.sessions.string_items.meta.updated_at)

      assert.equals(1, #result.sessions.no_meta.items)
      assert.equals("number", type(result.sessions.no_meta.meta.created_at))
      assert.equals("number", type(result.sessions.no_meta.meta.updated_at))

      assert.equals("number", type(result.sessions.bad_meta.meta.created_at))
      assert.equals("number", type(result.sessions.bad_meta.meta.updated_at))
    end)

    it("handles non-table sessions in version 2 data", function()
      local result = migrate.ensure({ version = 2, sessions = "bad" })
      assert.equals(2, result.version)
      assert.same({}, result.sessions)
    end)
  end)
end)
