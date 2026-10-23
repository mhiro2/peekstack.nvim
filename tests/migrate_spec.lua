local migrate = require("peekstack.persist.migrate")

describe("migrate", function()
  describe("supports", function()
    it("accepts only the store versions it can migrate", function()
      assert.is_true(migrate.supports(1))
      assert.is_true(migrate.supports(2))
      for _, version in ipairs({ 0, 3, 99, "2" }) do
        assert.is_false(migrate.supports(version), vim.inspect(version))
      end
      assert.is_false(migrate.supports(nil))
    end)
  end)

  describe("ensure", function()
    -- The persist layer refuses data without a supported version before it
    -- gets here, so that stores it cannot read are never overwritten; this
    -- fallback only covers direct callers.
    it("falls back to an empty store for data it cannot migrate", function()
      for _, input in ipairs({
        { name = "nil", value = nil },
        { name = "a string", value = "string" },
        { name = "a number", value = 42 },
        { name = "a boolean", value = true },
        { name = "a table without a version", value = { sessions = {} } },
        { name = "an unknown version", value = { version = 3, sessions = {} } },
      }) do
        assert.same({ version = 2, sessions = {} }, migrate.ensure(input.value), input.name)
      end
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
