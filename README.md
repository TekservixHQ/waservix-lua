# waservix (Lua)

[![tests](https://github.com/TekservixHQ/waservix-lua/actions/workflows/tests.yml/badge.svg)](https://github.com/TekservixHQ/waservix-lua/actions/workflows/tests.yml)

Lua client for the [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/).

WAservix links your own WhatsApp number by QR code (the same way WhatsApp Web does) and gives you a REST API to send text, images, documents, locations and polls, with webhooks for incoming messages and status updates.

- Lua 5.1 to 5.4 and LuaJIT; uses LuaSocket + LuaSec by default, or your own HTTP function (OpenResty...)
- Webhook check built in

## Install

```bash
luarocks install waservix
```

## Quick start

You need a Tekservix account with WAservix and the API key of your number (Devices in the dashboard). Keep it on your server.

```lua
local waservix = require "waservix"

local wa = waservix.new { api_key = os.getenv("WASERVIX_KEY") }

local res, err = wa:send_text("+15551234567", "Hello Aline, your order is ready")
if not res then error(err.message) end
print(res.msgId, res.status)  -- 58213  in_progress
```

Every method returns the API's `data` on success, or `nil, err` where `err` has `status`, `message`, `errors`, `body` and `retry_after`. A 503 means the number is reconnecting.

## Sending

```lua
wa:send_image("+15551234567", "https://example.com/product.jpg", "Back in stock")
wa:send_document("+15551234567", "https://example.com/inv-1042.pdf", "Invoice-1042.pdf", "Your invoice")
wa:send_location("+15551234567", -1.9441, 30.0619, "Our shop")

-- Anything the API supports, including groups (JID ending in @g.us)
wa:send_message("120363040000000000@g.us", { text = "Team meeting at 3pm" })
wa:send_message("+15551234567", { poll = { name = "Lunch?", options = { "Pizza", "Sushi" } } })
```

## Status, contacts and groups

```lua
local info = wa:get_message_info(58213)       -- queued, sent, delivered, read, played or failed
local check = wa:on_whatsapp("+15551234567")  -- { exists = true, jid = "..." }
local conn = wa:get_status()                  -- { status = "connected" }
wa:edit_message(58213, "Corrected text")      -- own text messages, about 15 minutes
local groups = wa:list_groups()
wa:request("POST", "/messages/read", { msgId = "3EB0X123456789" })   -- any other endpoint
```

## Webhooks

Each webhook request carries `X-Webhook-Signature`, which equals your number's webhook secret:

```lua
-- OpenResty
if not waservix.verify_webhook(ngx.var.http_x_webhook_signature, os.getenv("WASERVIX_WEBHOOK_SECRET")) then
  return ngx.exit(401)
end
```

## Use it responsibly

WAservix is not Meta's official WhatsApp Business Platform. There's no business verification and no per-conversation fee, but WhatsApp's spam rules apply to your number directly. Message people who expect to hear from you, warm up new numbers slowly and keep the built-in account protection on.

## More from Tekservix

- [SMS Gora SMS Gateway](https://tekservix.com/smsgora/): SMS through your own Android phones (`luarocks install smsgora`)
- [AI Sales Agent](https://tekservix.com/ai-sales-agent): answers customers on WhatsApp and SMS using your website's content
- [Website to App](https://tekservix.com/mobile-apps): turn your website into Android and iOS apps
- WAservix libraries for many more languages: [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
