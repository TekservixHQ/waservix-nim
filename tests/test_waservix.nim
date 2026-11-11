import std/[unittest, json]
import waservix

type Seen = object
  meth, url: string
  headers: seq[(string, string)]
  body: JsonNode

var seen: seq[Seen]

proc fake(status = 200, reply = """{"success":true,"data":{"msgId":58213,"status":"in_progress"}}"""): Transport =
  result = proc (m, url: string, headers: seq[(string, string)], body: string): (int, string, seq[(string, string)]) =
    seen.add(Seen(meth: m, url: url, headers: headers, body: if body.len > 0: parseJson(body) else: nil))
    (status, reply, newSeq[(string, string)]())

proc header(s: Seen, name: string): string =
  for (k, v) in s.headers:
    if k == name: return v

suite "waservix":
  setup:
    seen = @[]

  test "send text":
    let wa = newWAservix("wpk_test", baseUrl = "https://example.test/api", transport = fake())
    let res = wa.sendText("+1555", "hi")
    check res["msgId"].getInt == 58213
    check seen[0].url == "https://example.test/api/send-message"
    check seen[0].header("Authorization") == "Bearer wpk_test"
    check seen[0].body == %*{"text": "hi", "to": "+1555"}

  test "media and paths":
    let wa = newWAservix("k", baseUrl = "https://example.test/api", transport = fake())
    discard wa.sendImage("+1", "https://x/y.jpg")
    check not seen[0].body.hasKey("text")
    discard wa.sendDocument("+1", "https://x/a.pdf", "a.pdf", "c")
    check seen[1].body["fileName"].getStr == "a.pdf"
    discard wa.sendLocation("+1", -1.9441, 30.0619, "Shop")
    check seen[2].body["location"]["name"].getStr == "Shop"
    discard wa.getMessageInfo("5")
    check seen[3].url == "https://example.test/api/messages/5/info"
    discard wa.editMessage("5", "t")
    check seen[4].meth == "PUT"
    discard wa.onWhatsApp("+1555")
    check seen[5].url == "https://example.test/api/on-whatsapp/%2B1555"
    discard wa.getGroupMetadata("1203@g.us")
    check seen[6].url == "https://example.test/api/groups/1203%40g.us/metadata"
    discard wa.connectSession("3")
    check seen[7].body == %*{"method": "qr"}
    discard wa.connectSession("3", "+1555")
    check seen[8].body == %*{"method": "code", "phone": "+1555"}
    expect ValueError:
      discard wa.sendText("", "x")
    expect ValueError:
      discard newWAservix("")

  test "API errors":
    let wa = newWAservix("k", transport = fake(503, """{"success":false,"message":"Device reconnecting"}"""))
    try:
      discard wa.getStatus()
      check false
    except WAservixError as e:
      check e.status == 503
      check e.msg == "Device reconnecting"
    let wa2 = newWAservix("k", transport = fake(200, """{"success":false,"message":"Invalid number"}"""))
    try:
      discard wa2.sendText("+1", "x")
      check false
    except WAservixError as e:
      check e.msg == "Invalid number"

  test "webhook secret":
    check verifyWebhook("abc", "abc")
    check not verifyWebhook("abd", "abc")
    check not verifyWebhook("abcd", "abc")
    check not verifyWebhook("", "abc")
