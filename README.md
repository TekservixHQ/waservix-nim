# waservix (Nim)

[![tests](https://github.com/TekservixHQ/waservix-nim/actions/workflows/tests.yml/badge.svg)](https://github.com/TekservixHQ/waservix-nim/actions/workflows/tests.yml)

Nim client for the [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/).

WAservix links your own WhatsApp number by QR code (the same way WhatsApp Web does) and gives you a REST API to send text, images, documents, locations and polls, with webhooks for incoming messages.

## Install

```bash
nimble install https://github.com/TekservixHQ/waservix-nim
```

Compile your program with `-d:ssl` (HTTPS). Nim 1.6+, no dependencies.

## Usage

You need a Tekservix account with WAservix and your number's API key (Devices in the dashboard). Keep it on your server.

```nim
import std/[os, json], waservix

let wa = newWAservix(getEnv("WASERVIX_KEY"))

let res = wa.sendText("+15551234567", "Hello Aline, your order is ready")
echo res["msgId"].getInt     # 58213 (status "in_progress")

discard wa.sendImage("+15551234567", "https://example.com/product.jpg", "Back in stock")
discard wa.sendDocument("+15551234567", "https://example.com/inv-1042.pdf", "Invoice-1042.pdf", "Your invoice")
discard wa.sendLocation("+15551234567", -1.9441, 30.0619, "Our shop")
discard wa.sendMessage("120363040000000000@g.us", %*{"text": "Team meeting at 3pm"})

echo wa.getMessageInfo("58213")     # queued, sent, delivered, read, played or failed
echo wa.onWhatsApp("+15551234567")  # {"exists": true, "jid": ...}
echo wa.getStatus()                 # {"status": "connected"}
echo wa.request("GET", "/groups")   # any other endpoint
```

Failed calls raise `WAservixError` with `status`, `msg`, `errors`, `body` and `retryAfter`. A 503 means the number is reconnecting.

Webhooks carry `X-Webhook-Signature`, which equals your number's webhook secret: check it with `verifyWebhook(signature, secret)`.

WAservix is not Meta's official WhatsApp Business Platform: WhatsApp's spam rules apply to your number, so only message people who expect to hear from you.

## More from Tekservix

- [SMS Gora SMS Gateway](https://tekservix.com/smsgora/) ([Nim client](https://github.com/TekservixHQ/smsgora-nim))
- [AI Sales Agent](https://tekservix.com/ai-sales-agent) and [Website to App](https://tekservix.com/mobile-apps)
- WAservix libraries for many more languages: [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
