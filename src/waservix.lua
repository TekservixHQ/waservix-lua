--- Lua client for the WAservix WhatsApp API Gateway (https://tekservix.com/waservix/).
--
--   local waservix = require "waservix"
--   local wa = waservix.new{ api_key = os.getenv("WASERVIX_KEY") }
--   local res, err = wa:send_text("+15551234567", "Hello Aline, your order is ready")
--
-- Every method returns `data` on success, or `nil, err` where err is a table with
-- status, message, errors, body and retry_after. A 503 means the number is reconnecting.

local ok_json, json = pcall(require, "cjson")
if not ok_json then json = require "dkjson" end

local M = { _VERSION = "1.0.1" }
M.DEFAULT_BASE_URL = "https://tekservix.com/waservix/api"

local Client = {}
Client.__index = Client

-- Default transport: LuaSocket + LuaSec. Returns status, body, headers.
local function default_http(method, url, headers, body)
  local ltn12 = require "ltn12"
  local requester = url:match("^https:") and require("ssl.https") or require("socket.http")
  local chunks = {}
  local _, status, resp_headers = requester.request {
    method = method,
    url = url,
    headers = headers,
    source = body and ltn12.source.string(body) or nil,
    sink = ltn12.sink.table(chunks),
  }
  if type(status) ~= "number" then return nil, tostring(status) end
  return status, table.concat(chunks), resp_headers or {}
end

local function esc(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function decode(text)
  if text == nil or text == "" then return nil end
  local ok, value = pcall(json.decode, text)
  if ok and value ~= json.null then return value end
  return nil
end

--- Create a client.
-- opts.api_key (required), opts.base_url, opts.http = function(method, url, headers, body) -> status, body, headers
function M.new(opts)
  assert(type(opts) == "table" and type(opts.api_key) == "string" and opts.api_key ~= "",
    "waservix: api_key is required (Devices -> API key in the WAservix dashboard)")
  return setmetatable({
    api_key = opts.api_key,
    base_url = (opts.base_url or M.DEFAULT_BASE_URL):gsub("/+$", ""),
    http = opts.http or default_http,
  }, Client)
end

--- Call any documented endpoint, e.g. wa:request("GET", "/groups").
function Client:request(method, path, body)
  local headers = {
    ["authorization"] = "Bearer " .. self.api_key,
    ["accept"] = "application/json",
    ["user-agent"] = "waservix-lua/" .. M._VERSION,
  }
  local payload
  if body ~= nil then
    payload = json.encode(body)
    headers["content-type"] = "application/json"
    headers["content-length"] = tostring(#payload)
  end

  local status, text, resp_headers = self.http(method:upper(), self.base_url .. path, headers, payload)
  if not status then
    return nil, { status = 0, message = "request failed: " .. tostring(text) }
  end
  local data = decode(text)
  local failed = type(data) == "table" and data.success == false
  if status >= 400 or failed then
    local retry = resp_headers and (resp_headers["retry-after"] or resp_headers["Retry-After"])
    return nil, {
      status = status,
      message = type(data) == "table" and type(data.message) == "string" and data.message or ("HTTP " .. status),
      errors = type(data) == "table" and data.errors or nil,
      body = data or text,
      retry_after = tonumber(retry),
    }
  end
  if type(data) == "table" and data.data ~= nil then return data.data end
  return data
end

--- Send any message type to a number or group JID (...@g.us). fields uses the API names:
-- text, imageUrl, videoUrl, audioUrl, documentUrl, fileName, stickerUrl, contact, location,
-- poll, replyTo, mentions, viewOnce. Returns { msgId, jid, status = "in_progress" }.
function Client:send_message(to, fields)
  if type(to) ~= "string" or to == "" then
    return nil, { status = 0, message = 'send_message: "to" is required (international number or group JID)' }
  end
  local body = {}
  for k, v in pairs(fields or {}) do body[k] = v end
  body.to = to
  return self:request("POST", "/send-message", body)
end

function Client:send_text(to, text) return self:send_message(to, { text = text }) end

function Client:send_image(to, image_url, caption)
  return self:send_message(to, { imageUrl = image_url, text = caption })
end

function Client:send_document(to, document_url, file_name, caption)
  return self:send_message(to, { documentUrl = document_url, fileName = file_name, text = caption })
end

function Client:send_location(to, latitude, longitude, name)
  return self:send_message(to, { location = { latitude = latitude, longitude = longitude, name = name } })
end

function Client:get_message_info(id) return self:request("GET", "/messages/" .. esc(id) .. "/info") end
function Client:edit_message(id, text) return self:request("PUT", "/messages/" .. esc(id), { text = text }) end
function Client:delete_message(id) return self:request("DELETE", "/messages/" .. esc(id)) end
function Client:resend_message(id) return self:request("POST", "/messages/" .. esc(id) .. "/resend") end

function Client:on_whatsapp(phone) return self:request("GET", "/on-whatsapp/" .. esc(phone)) end
function Client:get_status() return self:request("GET", "/status") end
function Client:get_user() return self:request("GET", "/user") end
function Client:list_contacts() return self:request("GET", "/contacts") end
function Client:get_contact(phone) return self:request("GET", "/contacts/" .. esc(phone)) end
function Client:save_contact(phone, name) return self:request("PUT", "/contacts", { phone = phone, name = name }) end
function Client:list_groups() return self:request("GET", "/groups") end
function Client:get_group_metadata(jid) return self:request("GET", "/groups/" .. esc(jid) .. "/metadata") end

function Client:list_sessions() return self:request("GET", "/whatsapp-sessions") end
function Client:get_session(id) return self:request("GET", "/whatsapp-sessions/" .. esc(id)) end
function Client:create_session(params) return self:request("POST", "/whatsapp-sessions", params or {}) end

function Client:connect_session(id, phone)
  local body = phone and { method = "code", phone = phone } or { method = "qr" }
  return self:request("POST", "/whatsapp-sessions/" .. esc(id) .. "/connect", body)
end

function Client:get_session_qr_code(id) return self:request("GET", "/whatsapp-sessions/" .. esc(id) .. "/qrcode") end

--- Constant-time check of the X-Webhook-Signature header against the number's webhook secret.
function M.verify_webhook(signature, secret)
  if type(signature) ~= "string" or signature == "" or type(secret) ~= "string" or secret == "" then
    return false
  end
  if #signature ~= #secret then return false end
  local same = true
  for i = 1, #secret do
    if signature:byte(i) ~= secret:byte(i) then same = false end
  end
  return same
end

return M
