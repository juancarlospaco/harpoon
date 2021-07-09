import std/[net, asyncnet, asyncdispatch, macros]
from std/strutils import split, toLowerAscii, join, parseInt, startsWith, endsWith
from std/times import now, inMilliseconds, `-`
from std/httpcore import HttpMethod, HttpCode
from std/importutils import privateAccess
from std/parseutils import parseHex
from std/uri import Uri, parseUri
from std/base64 import encode
export HttpMethod, HttpCode

template newDefaultHeaders*(body: string; contentType = "text/plain"; accept = "*/*"; userAgent = "x"): array[4, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept)]

template newDefaultHeaders*(body: string; doNotTrack: bool; contentType = "application/json"; accept = "application/json"; userAgent = "x"): array[5, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept), ("Dnt", if doNotTrack: "1" else: "0")]

template newDefaultHeaders*(body: string; proxyUser: string; proxyPassword: string; contentType = "text/plain"; accept = "*/*"; userAgent = "x"): array[5, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept), ("Proxy-Authorization", "Basic " & encode(proxyUser & ':' & proxyPassword))]

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

func parseHeaders(data: string): seq[(string, string)] {.raises: [].} =
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

func toString(url: Uri; metod: HttpMethod; headers: openArray[(string, string)]; body: string): string {.raises: [].} =
  var it: char  # TODO: Better name for this func.
  var temp: string = url.path
  if unlikely(temp.len == 0): temp = "/"
  if url.query.len > 0:
    temp.add '?'
    temp.add url.query
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
  result.add temp
  for _ in unrollStringOps(" HTTP/1.1\r\nHost: ", it): result.add it
  result.add url.hostname
  for _ in unrollStringOps("\r\n", it): result.add it
  temp.setLen 0  # Reuse variable.
  for header in headers:
    temp.add header[0]
    for _ in unrollStringOps(": ", it):   temp.add it
    temp.add header[1]
    for _ in unrollStringOps("\r\n", it): temp.add it
  for _ in unrollStringOps("\r\n", it):   temp.add it
  assert not(temp.len > 10_000), "Header must not be > 10_000 char"
  result.add temp
  result.add body

proc fetch*(socket: Socket; url: Uri; metod: HttpMethod; headers: openArray[(string, string)]; body = "";
    timeout = -1; proxyUrl = ""; port = 80.Port; portSsl = 442.Port;
    parseHeader = true; parseStatus = true; parseBody = true; ignoreErrors = false; bodyOnly: static[bool] = false): auto {.raises: [IOError, OSError, TimeoutError, SslError, ValueError].} =
  assert timeout > -2 and timeout != 0, "Timeout argument must be -1 or a non-zero positive integer"
  var
    res: string
    chunked: bool
    contentLength: int
    chunks: seq[string]
  let
    flag = if ignoreErrors: {} else: {SafeDisconn}
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
    chunks.add chunk
  when bodyOnly: result = chunks.join
  else:
    privateAccess url.type  # To use Uri.isIpv6
    result = (url: url, metod: metod, isIpv6: url.isIpv6,
              headers: if parseHeader: parseHeaders(res)  else: @[],
              code:    if parseStatus: parseHttpCode(res).HttpCode else: 0.HttpCode,
              body:    if parseBody:   chunks.join        else: "" )

proc fetch*(socket: AsyncSocket; url: string; metod: HttpMethod; headers: seq[(string, string)]; body = "";
    timeout = -1; proxyUrl = ""; port = 80.Port; portSsl = 442.Port;
    parseHeader = true; parseStatus = true; parseBody = true; ignoreErrors = false
    ): Future[tuple[url: Uri, metod: HttpMethod, isIpv6: bool, headers: seq[(string, string)], code: HttpCode, body: string]] {.async, raises: [IOError, OSError, SslError, ValueError, Exception].} =
  assert timeout > -2 and timeout != 0, "Timeout argument must be -1 or a non-zero positive integer"
  assert url.len > 0, "URL must not be empty string"
  template timeoutImpl() =
    if unlikely(timeout != -1 and (now() - t0).inMilliseconds > timeout): return
  var
    res: string
    chunked: bool
    contentLength: int
    chunks: seq[string]
  let
    t0 = now()
    flag = if ignoreErrors: {} else: {SafeDisconn}
    url: Uri = parseUri(url)
    proxi: string = if unlikely(proxyUrl.len > 0): proxyUrl else: url.hostname
  if likely(url.scheme == "https"):
    var ctx =
      try:    newContext(verifyMode = CVerifyPeer)
      except: raise newException(IOError, getCurrentExceptionMsg())
    await socket.connect(proxi, portSsl)
    timeoutImpl()
    try:    ctx.wrapConnectedSocket(socket, handshakeAsClient, proxi)
    except: raise newException(IOError, getCurrentExceptionMsg())
  else:
    await socket.connect(proxi, port)
    timeoutImpl()
  await socket.send(toString(url, metod, headers, body), flags = flag)
  timeoutImpl()
  while true:
    let line = await socket.recvLine(flags = flag)
    res.add line
    res.add '\r'
    res.add '\n'
    let lineLower = line.toLowerAscii()
    if line == "\r\n":                              break
    elif lineLower.startsWith("content-length:"):   contentLength = parseInt(line.split(' ')[1])
    elif lineLower == "transfer-encoding: chunked": chunked = true
    timeoutImpl()
  if chunked:
    while true:
      var chunkLenStr: string
      while true:
        var readChar: char
        let readLen = await socket.recvInto(readChar.addr, 1)
        doAssert readLen == 1
        chunkLenStr.add(readChar)
        if chunkLenStr.endsWith("\r\n"): break
        timeoutImpl()
      if chunkLenStr == "\r\n": break
      var chunkLen: int
      discard parseHex(chunkLenStr, chunkLen)
      if chunkLen == 0: break
      var chunk = newString(chunkLen)
      let readLen = await socket.recvInto(chunk[0].addr, chunkLen)
      doAssert readLen == chunkLen
      chunks.add(chunk)
      var endStr = newString(2)
      let readLen2 = await socket.recvInto(endStr[0].addr, 2)
      assert endStr == "\r\n"
      timeoutImpl()
  else:
    var chunk = newString(contentLength)
    let readLen = await socket.recvInto(chunk[0].addr, contentLength)
    assert readLen == contentLength
    chunks.add chunk
    timeoutImpl()
  privateAccess url.type  # To use Uri.isIpv6
  result = (url: url, metod: metod, isIpv6: url.isIpv6,
            headers: if parseHeader: parseHeaders(res)  else: @[],
            code:    if parseStatus: parseHttpCode(res).HttpCode else: 0.HttpCode,
            body:    if parseBody:   chunks.join        else: "" )

template asyncFetchImpl(url: string; bodi: string; metod: static[HttpMethod]): untyped {.dirty.} =
  let asincSocket: AsyncSocket = newAsyncSocket()
  try: result = await(fetch(asincSocket, url, metod, @(newDefaultHeaders(bodi)), parseHeader = false, parseStatus = false)).body
  finally: close asincSocket

template fetchImpl(code): untyped {.dirty.} =
  let socket: Socket = newSocket()
  defer: close socket
  code

proc get*(url: Uri): auto =
  fetchImpl(socket.fetch(url, HttpGet, newDefaultHeaders""))

proc getContent*(url: Uri): string =
  fetchImpl(socket.fetch(url, HttpGet, newDefaultHeaders"", bodyOnly = true))

proc post*(url: Uri; body: string): auto =
  fetchImpl(socket.fetch(url, HttpPost, newDefaultHeaders(body), body))

proc postContent*(url: Uri; body: string): string =
  fetchImpl(socket.fetch(url, HttpPost, newDefaultHeaders(body), body, bodyOnly = true))

proc put*(url: Uri; body: string): auto =
  fetchImpl(socket.fetch(url, HttpPut, newDefaultHeaders(body), body))

proc putContent*(url: Uri; body: string): string =
  fetchImpl(socket.fetch(url, HttpPut, newDefaultHeaders(body), body, bodyOnly = true))

proc patch*(url: Uri; body: string): auto =
  fetchImpl(socket.fetch(url, HttpPatch, newDefaultHeaders(body), body))

proc patchContent*(url: Uri; body: string): string =
  fetchImpl(socket.fetch(url, HttpPatch, newDefaultHeaders(body), body, bodyOnly = true))

proc delete*(url: Uri): auto =
  fetchImpl(socket.fetch(url, HttpDelete, newDefaultHeaders""))

proc deleteContent*(url: Uri): string =
  fetchImpl(socket.fetch(url, HttpDelete, newDefaultHeaders"", bodyOnly = true))

proc downloadFile*(url: Uri; filename: string) =
  assert filename.len > 0, "filename must not be an empty string"
  fetchImpl(writeFile(filename, socket.fetch(url, HttpGet, newDefaultHeaders"", bodyOnly = true)))

proc downloadFile*(files: openArray[tuple[url: Uri; path: string]]) =
  assert files.len > 0, "files must not be empty"
  let socket: Socket = newSocket()
  try:
    for url_file in files:
      assert url_file.path.len > 0, "path must not be empty string"
      writeFile(url_file.path, socket.fetch(url_file.url, HttpGet, newDefaultHeaders"", bodyOnly = true))
  finally: close socket

proc getContent*(url: string): Future[string] {.async.} =
  asyncFetchImpl(url, "", HttpGet)

proc postContent*(url: string; body: string): Future[string] {.async.} =
  asyncFetchImpl(url, body, HttpPost)

proc putContent*(url: string; body: string): Future[string] {.async.} =
  asyncFetchImpl(url, body, HttpPut)

proc patchContent*(url: string; body: string): Future[string] {.async.} =
  asyncFetchImpl(url, body, HttpPatch)

proc deleteContent*(url: string): Future[string] {.async.} =
  asyncFetchImpl(url, "", HttpDelete)

proc downloadFile*(url: string; filename: string): Future[void] {.async.} =
  assert filename.len > 0, "filename must not be an empty string"
  let asincSocket: AsyncSocket = newAsyncSocket()
  try: writeFile(filename, await(fetch(asincSocket, url, HttpGet, @(newDefaultHeaders""))).body)
  finally: close asincSocket

runnableExamples"--gc:orc --experimental:strictFuncs -d:ssl -d:nimStressOrc --import:std/httpcore":
  import std/asyncdispatch      # Async works. Can work with Threads, Tasks, Macros, etc.
  from std/uri import parseUri  # To use Uri.
  block:
    doAssert get(parseUri"http://httpbin.org/get").code == Http200
    doAssert getContent(parseUri"http://httpbin.org/get").len > 0
  block:
    doAssert post(parseUri"http://httpbin.org/post", "data here").code == Http200
    doAssert postContent(parseUri"http://httpbin.org/post", "data here").len > 0
  block:
    doAssert delete(parseUri"http://httpbin.org/delete").code == Http200
    doAssert deleteContent(parseUri"http://httpbin.org/delete").len > 0
  block:
    doAssert put(parseUri"http://httpbin.org/put", "data here").code == Http200
    doAssert putContent(parseUri"http://httpbin.org/put", "data here").len > 0
  block:
    doAssert patch(parseUri"http://httpbin.org/patch", "data here").code == Http200
    doAssert patchContent(parseUri"http://httpbin.org/patch", "data here").len > 0
  block:
    downloadFile parseUri"http://httpbin.org/image/png", "temp.png"
    downloadFile [(url: parseUri"http://httpbin.org/image/png", path: "temp.png"), (url: parseUri"http://httpbin.org/image/jpg", path: "temp.jpg")]
    doAssert newDefaultHeaders(body = "data here", proxyUser = "root", proxyPassword = "password") is array[5, (string, string)]
  block:
    proc example() {.async, used.} =
      doAssert getContent("http://httpbin.org/get") is Future[string]
      doAssert deleteContent("http://httpbin.org/delete") is Future[string]
      doAssert putContent("http://httpbin.org/put", "data here") is Future[string]
      doAssert postContent("http://httpbin.org/post", "data here") is Future[string]
      doAssert patchContent("http://httpbin.org/patch", "data here") is Future[string]
      doAssert downloadFile("http://httpbin.org/image/png", "temp.png") is Future[void]
    waitFor example()
