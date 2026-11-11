# Package

version       = "1.0.0"
author        = "Tekservix"
description   = "Nim client for the WAservix WhatsApp API Gateway: send WhatsApp messages from your own number"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.6.0"

task test, "Run the tests":
  exec "nim c -r --hints:off tests/test_waservix.nim"
