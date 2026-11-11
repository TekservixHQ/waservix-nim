## Nim client for the WAservix WhatsApp API Gateway (https://tekservix.com/waservix/).
##
## .. code-block:: nim
##   import waservix
##   let wa = newWAservix(getEnv("WASERVIX_KEY"))
##   let res = wa.sendText("+15551234567", "Hello Aline, your order is ready")
##   echo res["msgId"].getInt   # 58213
##
## Needs a Tekservix account with WAservix and your number's API key. Keep it on your server.
## Compile with `-d:ssl` for HTTPS.

import std/[httpclient, json, strutils, uri]

const
  WAservixVersion* = "1.0.0"
  DefaultBaseUrl* = "https://tekservix.com/waservix/api"

type
  WAservixError* = object of CatchableError
    ## Raised when the API answers with an error. A 503 means the number is reconnecting.
    status*: int
    errors*: JsonNode
    body*: string
    retryAfter*: float

  Transport* = proc (httpMethod, url: string, headers: seq[(string, string)], body: string): (int, string, seq[(string, string)]) {.closure.}
    ## Sends a request; returns (status, body, response headers). Replace it for tests or proxies.

  WAservix* = ref object
    apiKey: string
    baseUrl*: string
    transport: Transport

proc defaultTransport(timeoutMs: int): Transport =
  result = proc (httpMethod, url: string, headers: seq[(string, string)], body: string): (int, string, seq[(string, string)]) =
    let client = newHttpClient(timeout = timeoutMs)
    defer: client.close()
    client.headers = newHttpHeaders(headers)
    let resp = client.request(url, httpMethod = parseEnum[HttpMethod](httpMethod), body = body)
    var hs: seq[(string, string)]
    for k, v in resp.headers.pairs: hs.add((k.toLowerAscii, v))
    (resp.code.int, resp.body, hs)

proc newWAservix*(apiKey: string, baseUrl = DefaultBaseUrl, timeoutMs = 30_000, transport: Transport = nil): WAservix =
  ## Client with your number's API key (Devices in the WAservix dashboard).
  if apiKey.len == 0:
    raise newException(ValueError, "WAservix: apiKey is required (Devices -> API key in the WAservix dashboard)")
  WAservix(apiKey: apiKey, baseUrl: baseUrl.strip(leading = false, chars = {'/'}),
           transport: if transport.isNil: defaultTransport(timeoutMs) else: transport)

proc esc(s: string): string = encodeUrl(s, usePlus = false)

proc request*(c: WAservix, httpMethod, path: string, body: JsonNode = nil): JsonNode =
  ## Call any documented endpoint, e.g. `c.request("GET", "/groups")`. Returns the `data` field.
  var headers = @[("Authorization", "Bearer " & c.apiKey), ("Accept", "application/json"),
                  ("User-Agent", "waservix-nim/" & WAservixVersion)]
  var payload = ""
  if not body.isNil:
    headers.add(("Content-Type", "application/json"))
    payload = $body
  var status: int
  var text: string
  var respHeaders: seq[(string, string)]
  try:
    (status, text, respHeaders) = c.transport(httpMethod.toUpperAscii, c.baseUrl & path, headers, payload)
  except CatchableError as e:
    var err = newException(WAservixError, "WAservix: request failed (" & e.msg & ")")
    err.status = 0
    raise err
  var data: JsonNode = nil
  if text.len > 0:
    try: data = parseJson(text) except CatchableError: data = nil
  let isObj = not data.isNil and data.kind == JObject
  if status >= 400 or (isObj and data.hasKey("success") and data["success"].kind == JBool and not data["success"].getBool):
    let msg = if isObj and data.hasKey("message") and data["message"].kind == JString: data["message"].getStr else: "HTTP " & $status
    var err = newException(WAservixError, msg)
    err.status = status
    err.errors = if isObj and data.hasKey("errors"): data["errors"] else: nil
    err.body = text
    for (k, v) in respHeaders:
      if k == "retry-after":
        try: err.retryAfter = parseFloat(v.strip) except ValueError: discard
    raise err
  if isObj and data.hasKey("data"): return data["data"]
  if data.isNil: newJNull() else: data

proc sendMessage*(c: WAservix, to: string, fields: JsonNode): JsonNode =
  ## Send any message type to a number or group JID (`...@g.us`). `fields` uses the API names:
  ## text, imageUrl, videoUrl, audioUrl, documentUrl, fileName, stickerUrl, contact, location,
  ## poll, replyTo, mentions, viewOnce. Returns `{"msgId", "jid", "status": "in_progress"}`.
  if to.len == 0: raise newException(ValueError, "sendMessage: \"to\" is required (international number or group JID)")
  let body = newJObject()
  if not fields.isNil and fields.kind == JObject:
    for k, v in fields.pairs:
      if v.kind != JNull: body[k] = v
  body["to"] = %to
  c.request("POST", "/send-message", body)

proc sendText*(c: WAservix, to, text: string): JsonNode = c.sendMessage(to, %*{"text": text})

proc sendImage*(c: WAservix, to, imageUrl: string, caption = ""): JsonNode =
  let f = %*{"imageUrl": imageUrl}
  if caption.len > 0: f["text"] = %caption
  c.sendMessage(to, f)

proc sendDocument*(c: WAservix, to, documentUrl: string, fileName = "", caption = ""): JsonNode =
  let f = %*{"documentUrl": documentUrl}
  if fileName.len > 0: f["fileName"] = %fileName
  if caption.len > 0: f["text"] = %caption
  c.sendMessage(to, f)

proc sendLocation*(c: WAservix, to: string, latitude, longitude: float, name = ""): JsonNode =
  let loc = %*{"latitude": latitude, "longitude": longitude}
  if name.len > 0: loc["name"] = %name
  c.sendMessage(to, %*{"location": loc})

proc getMessageInfo*(c: WAservix, id: string): JsonNode =
  ## Status: queued, sent, delivered, read, played or failed.
  c.request("GET", "/messages/" & esc(id) & "/info")

proc editMessage*(c: WAservix, id, text: string): JsonNode =
  ## Edit one of your own text messages (about 15 minutes after sending).
  c.request("PUT", "/messages/" & esc(id), %*{"text": text})

proc deleteMessage*(c: WAservix, id: string): JsonNode = c.request("DELETE", "/messages/" & esc(id))
proc resendMessage*(c: WAservix, id: string): JsonNode = c.request("POST", "/messages/" & esc(id) & "/resend")

proc onWhatsApp*(c: WAservix, phone: string): JsonNode =
  ## Is this number on WhatsApp? Returns `{"exists": true/false, "jid": ...}`.
  c.request("GET", "/on-whatsapp/" & esc(phone))

proc getStatus*(c: WAservix): JsonNode =
  ## connected, connecting, need_scan, disconnected, logged_out or expired.
  c.request("GET", "/status")

proc getUser*(c: WAservix): JsonNode = c.request("GET", "/user")
proc listContacts*(c: WAservix): JsonNode = c.request("GET", "/contacts")
proc getContact*(c: WAservix, phone: string): JsonNode = c.request("GET", "/contacts/" & esc(phone))
proc saveContact*(c: WAservix, phone, name: string): JsonNode = c.request("PUT", "/contacts", %*{"phone": phone, "name": name})
proc listGroups*(c: WAservix): JsonNode = c.request("GET", "/groups")
proc getGroupMetadata*(c: WAservix, jid: string): JsonNode = c.request("GET", "/groups/" & esc(jid) & "/metadata")

proc listSessions*(c: WAservix): JsonNode =
  ## Sessions need a personal access token, not a device key.
  c.request("GET", "/whatsapp-sessions")

proc getSession*(c: WAservix, id: string): JsonNode = c.request("GET", "/whatsapp-sessions/" & esc(id))
proc createSession*(c: WAservix, params: JsonNode = newJObject()): JsonNode = c.request("POST", "/whatsapp-sessions", params)

proc connectSession*(c: WAservix, id: string, phone = ""): JsonNode =
  ## Connect by QR code, or by pairing code when `phone` is given.
  let body = if phone.len > 0: %*{"method": "code", "phone": phone} else: %*{"method": "qr"}
  c.request("POST", "/whatsapp-sessions/" & esc(id) & "/connect", body)

proc getSessionQrCode*(c: WAservix, id: string): JsonNode = c.request("GET", "/whatsapp-sessions/" & esc(id) & "/qrcode")

proc verifyWebhook*(signature, secret: string): bool =
  ## Constant-time check of the `X-Webhook-Signature` header against your number's webhook secret.
  if signature.len == 0 or secret.len == 0 or signature.len != secret.len: return false
  var diff = 0
  for i in 0 ..< secret.len: diff = diff or (ord(signature[i]) xor ord(secret[i]))
  diff == 0
