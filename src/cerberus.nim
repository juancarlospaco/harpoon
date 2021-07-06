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
  for header in headers:
    result.add header[0]
    for _ in unrollStringOps(": ", it): result.add it
    result.add header[1]
    for _ in unrollStringOps("\r\n", it): result.add it
  assert not headers.len > 10_000, "Header must not be > 10_000 chars"
  for _ in unrollStringOps("\r\n", it): result.add it
  result.add body

proc fetch*(socket: Socket; url: string or Uri; metod: HttpMethod; body = ""; headers: openArray[(string, string)];
    timeout = -1; userAgent = "nim/http"; proxyUrl = ""; port = 80.Port; portSsl = 442.Port;
    parseHeader = true; parseStatus = true; parseBody = true; ignoreErrors = false; bodyOnly: static[bool] = false): auto =
  var
    res: string
    chunked: bool
    contentLength: int
    chunks: seq[string]
  let
    flag = if ignoreErrors: {} else: {SafeDisconn}
    url: Uri = when url is Uri: url else: parseUri(url)
    proxi: string = if unlikely(proxyUrl.len > 0): proxyUrl else: url.hostname
  if likely(url.scheme == "https"):
    var ctx =
      try:    newContext(verifyMode = CVerifyPeer)
      except: raise newException(IOError, getCurrentExceptionMsg())
    socket.connect(proxi, portSsl, timeout)
    try:    ctx.wrapConnectedSocket(socket, handshakeAsClient, proxi)
    except: raise newException(IOError, getCurrentExceptionMsg())
  else: socket.connect(proxi, port, timeout)
  if ignoreErrors: discard socket.trySend(toString(url, metod, headers, body))
  else:            socket.send(toString(url, metod, headers, body), flags = flag)
  while true:
    let line = socket.recvLine(timeout, flags = flag)
    res.add line
    res.add '\r'
    res.add '\n'
    let lineLower = line.toLowerAscii()
    if line == "\r\n":                              break
    elif lineLower.startsWith("content-length:"):   contentLength = parseInt(line.split(' ')[1])
    elif lineLower == "transfer-encoding: chunked": chunked = true
  if chunked:
    while true:
      var chunkLenStr: string
      while true:
        var readChar: char
        let readLen = socket.recv(readChar.addr, 1, timeout)
        doAssert readLen == 1
        chunkLenStr.add(readChar)
        if chunkLenStr.endsWith("\r\n"): break
      if chunkLenStr == "\r\n": break
      var chunkLen: int
      discard parseHex(chunkLenStr, chunkLen)
      if chunkLen == 0: break
      var chunk = newString(chunkLen)
      let readLen = socket.recv(chunk[0].addr, chunkLen, timeout)
      doAssert readLen == chunkLen
      chunks.add(chunk)
      var endStr = newString(2)
      let readLen2 = socket.recv(endStr[0].addr, 2, timeout)
      assert endStr == "\r\n"
  else:
    var chunk = newString(contentLength)
    let readLen = socket.recv(chunk[0].addr, contentLength, timeout)
    assert readLen == contentLength
    chunks.add(chunk[0 .. ^2])
  when bodyOnly: result = chunks.join
  else:
    privateAccess url.type     # To use Uri.isIpv6
    result = (url: url, metod: metod, isIpv6: url.isIpv6,
              headers: if parseHeader: parseHeaders(res)  else: @[],
              code:    if parseStatus: parseHttpCode(res) else: 0  ,
              body:    if parseBody:   chunks.join        else: "" )


const bodi = """field1=value1"""
const h = newDefaultHeaders(bodi)
let socket: Socket = newSocket()
echo socket.fetch("http://httpbin.org/get?foo=bar", metod = HttpGet, body = "", headers = h, bodyOnly = true)
echo socket.fetch("http://httpbin.org/get?foo=bar", metod = HttpGet, body = "", headers = h, bodyOnly = true)
socket.close()
