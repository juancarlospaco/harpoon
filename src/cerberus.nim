import std/[os, net, uri, base64, macros, parseutils, strutils, httpcore, importutils]

const cacertUrl* = "https://curl.se/ca/cacert.pem"  # cacert.pem URL.

template newDefaultHeaders*(body = ""; userAgent = "x"; contentType = "text/plain"; accept = "*/*"): array[4, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept)]

template newDefaultHeaders*(body = ""; userAgent = "x"; contentType = "text/plain"; accept = "*/*"; proxyUser, proxyPassword: string): array[5, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept), ("Proxy-Authorization", "Basic " & base64.encode(proxyUser & ':' & proxyPassword))]

macro unrollStringOps(x: ForLoopStmt) =
  expectKind x, nnkForStmt
  var body = newStmtList()
  for chara in x[^2][^2].strVal:
    body.add nnkAsgn.newTree(x[^2][^1], chara.newLit)
    body.add x[^1]
  result = body

template parseHttpCode(s: string): int =
  template char2Int(c: '0'..'9'; pos: static int): int =
    case c
    of '1': static(1 * pos)
    of '2': static(2 * pos)
    of '3': static(3 * pos)
    of '4': static(4 * pos)
    of '5': static(5 * pos)
    of '6': static(6 * pos)
    of '7': static(7 * pos)
    of '8': static(8 * pos)
    of '9': static(9 * pos)
    else:   0
  char2Int(s[9], 100) + char2Int(s[10], 10) + char2Int(s[11], 1)

func parseHeaders*(data: string): seq[(string, string)] =
  var i = 0
  while data[i] != '\l': inc i
  inc i
  var value = false
  var current: (string, string)
  while i < data.len:
    case data[i]
    of ':':
      if value: current[1].add ':'
      value = true
    of ' ':
      if value:
        if current[1].len != 0: current[1].add data[i]
      else: current[0].add(data[i])
    of '\c': discard
    of '\l':
      if current[0].len == 0: return result
      result.add current
      value = false
      current = ("", "")
    else:
      if value: current[1].add data[i] else: current[0].add data[i]
    inc i
  return

func toString*(url: Uri; metod: HttpMethod; headers: openArray[(string, string)]; body: string): string =
  var it: char
  var path = url.path
  if path.len == 0: path = "/"
  if url.query.len > 0:
    path.add '?'
    path.add url.query
  case metod
  of HttpGet:
    for _ in unrollStringOps("GET ", it):     result.add it
  of HttpPost:
    for _ in unrollStringOps("POST ", it):    result.add it
  of HttpPut:
    for _ in unrollStringOps("PUT ", it):     result.add it
  of HttpHead:
    for _ in unrollStringOps("HEAD ", it):    result.add it
  of HttpDelete:
    for _ in unrollStringOps("DELETE ", it):  result.add it
  of HttpPatch:
    for _ in unrollStringOps("PATCH ", it):   result.add it
  of HttpTrace:
    for _ in unrollStringOps("TRACE ", it):   result.add it
  of HttpOptions:
    for _ in unrollStringOps("OPTIONS ", it): result.add it
  of HttpConnect:
    for _ in unrollStringOps("CONNECT ", it): result.add it
  result.add path
  for _ in unrollStringOps(" HTTP/1.1\r\nHost: ", it): result.add it
  result.add url.hostname
  for _ in unrollStringOps("\r\n", it): result.add it
  for header in headers:  # Headers have a soft limit of 10_000 char ?.
    result.add header[0]
    for _ in unrollStringOps(": ", it): result.add it
    result.add header[1]
    for _ in unrollStringOps("\r\n", it): result.add it
  for _ in unrollStringOps("\r\n", it): result.add it
  result.add body


# Imagine API like
const bodi = """field1=value1"""
const h = newDefaultHeaders(bodi)
let socket: Socket = newSocket()
echo socket.request("http://httpbin.org/get?foo=bar", metod = HttpGet, body = "", headers = h)
socket.close()
