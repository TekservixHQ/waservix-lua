local waservix = require "waservix"
local ok_json, json = pcall(require, "cjson")
if not ok_json then json = require "dkjson" end

local function fake(status, body)
  local calls = {}
  local http = function(method, url, h, payload)
    calls[#calls + 1] = { method = method, url = url, headers = h, body = payload and json.decode(payload) }
    return status or 200, body or '{"success":true,"data":{"msgId":58213,"status":"in_progress"}}', {}
  end
  return calls, http
end

describe("waservix", function()
  it("sends text", function()
    local calls, http = fake()
    local wa = waservix.new { api_key = "wpk_test", base_url = "https://example.test/api", http = http }
    local res = assert(wa:send_text("+1555", "hi"))
    assert.are.equal(58213, res.msgId)
    assert.are.equal("https://example.test/api/send-message", calls[1].url)
    assert.are.equal("Bearer wpk_test", calls[1].headers["authorization"])
    assert.are.same({ to = "+1555", text = "hi" }, calls[1].body)
  end)

  it("sends media and builds paths", function()
    local calls, http = fake()
    local wa = waservix.new { api_key = "k", base_url = "https://example.test/api", http = http }
    wa:send_image("+1", "https://x/y.jpg")
    assert.are.same({ to = "+1", imageUrl = "https://x/y.jpg" }, calls[1].body)
    wa:send_document("+1", "https://x/a.pdf", "a.pdf", "c")
    assert.are.equal("a.pdf", calls[2].body.fileName)
    wa:send_location("+1", -1.9441, 30.0619, "Shop")
    assert.are.equal("Shop", calls[3].body.location.name)
    wa:get_message_info(5)
    assert.are.equal("https://example.test/api/messages/5/info", calls[4].url)
    wa:edit_message(5, "t")
    assert.are.equal("PUT", calls[5].method)
    wa:on_whatsapp("+1555")
    assert.are.equal("https://example.test/api/on-whatsapp/%2B1555", calls[6].url)
    wa:get_group_metadata("1203@g.us")
    assert.are.equal("https://example.test/api/groups/1203%40g.us/metadata", calls[7].url)
    wa:connect_session(3)
    assert.are.same({ method = "qr" }, calls[8].body)
    wa:connect_session(3, "+1555")
    assert.are.same({ method = "code", phone = "+1555" }, calls[9].body)
    local res, err = wa:send_text("", "x")
    assert.is_nil(res)
    assert.truthy(err.message:find("required"))
  end)

  it("returns API errors", function()
    local _, http = fake(503, '{"success":false,"message":"Device reconnecting"}')
    local _, err = waservix.new({ api_key = "k", http = http }):get_status()
    assert.are.equal(503, err.status)
    assert.are.equal("Device reconnecting", err.message)

    local _, http2 = fake(200, '{"success":false,"message":"Invalid number"}')
    local _, err2 = waservix.new({ api_key = "k", http = http2 }):send_text("+1", "x")
    assert.are.equal("Invalid number", err2.message)

    assert.has_error(function() waservix.new {} end)
  end)

  it("verifies webhooks", function()
    assert.is_true(waservix.verify_webhook("abc", "abc"))
    assert.is_false(waservix.verify_webhook("abd", "abc"))
    assert.is_false(waservix.verify_webhook("abcd", "abc"))
    assert.is_false(waservix.verify_webhook(nil, "abc"))
  end)
end)
