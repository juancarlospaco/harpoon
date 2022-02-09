import std/[net,  macros, strutils, times, json, httpcore, importutils, parseutils, uri]

proc fetch*(socket: Socket; url: Uri; metod: static[HttpMethod];
    headers: openArray[(string, string)] = [("User-Agent", "x"), ("Content-Type", "text/plain"), ("Accept", "*/*"), ("Dnt", "1")];
    body = ""; timeout = -1; port: static[Port] = 80.Port; portSsl: static[Port] = 443.Port;
    parseHeader = true; parseStatus = true; parseBody = true; bodyOnly: static[bool] = false): auto =
  var
    res: string
    chunked: bool
    contentLength: int
    chunks: seq[string]

  template parseHttpCode(s: string): int {.used.} =
    when defined(danger):
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
    else: parseInt(s[9..11])

  func parseHeaders(data: string): seq[(string, string)] {.inline, used, raises: [].} =
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

  func toString(url: Uri; metod: static[HttpMethod]; headers: openArray[(string, string)]; body: string): string {.raises: [].} =
    var it: char
    var temp: string = url.path
    macro unrollStringOps(x: ForLoopStmt) =
      result = newStmtList()
      for chara in x[^2][^2].strVal:
        result.add nnkAsgn.newTree(x[^2][^1], chara.newLit)
        result.add x[^1]
    if unlikely(temp.len == 0): temp = "/"
    if url.query.len > 0:
      temp.add '?'
      temp.add url.query
    when metod == HttpGet:
      for _ in unrollStringOps("GET ", it):     result.add it
    elif metod == HttpPost:
      for _ in unrollStringOps("POST ", it):    result.add it
    elif metod == HttpPut:
      for _ in unrollStringOps("PUT ", it):     result.add it
    elif metod == HttpHead:
      for _ in unrollStringOps("HEAD ", it):    result.add it
    elif metod == HttpDelete:
      for _ in unrollStringOps("DELETE ", it):  result.add it
    elif metod == HttpPatch:
      for _ in unrollStringOps("PATCH ", it):   result.add it
    elif metod == HttpTrace:
      for _ in unrollStringOps("TRACE ", it):   result.add it
    elif metod == HttpOptions:
      for _ in unrollStringOps("OPTIONS ", it): result.add it
    elif metod == HttpConnect:
      for _ in unrollStringOps("CONNECT ", it): result.add it
    result.add temp
    for _ in unrollStringOps(" HTTP/1.1\r\nHost: ", it): result.add it
    result.add url.hostname
    for _ in unrollStringOps("\r\n", it): result.add it
    temp.setLen 0
    for header in headers:
      temp.add header[0]
      for _ in unrollStringOps(": ", it):   temp.add it
      temp.add header[1]
      for _ in unrollStringOps("\r\n", it): temp.add it
    for _ in unrollStringOps("\r\n", it):   temp.add it
    result.add temp
    result.add body

  if likely(url.scheme == "https"):
    var ctx =
      try:    newContext(verifyMode = CVerifyNone)
      except: raise newException(IOError, getCurrentExceptionMsg())
    socket.connect(url.hostname, portSsl, timeout)
    try:    ctx.wrapConnectedSocket(socket, handshakeAsClient, url.hostname)
    except: raise newException(IOError, getCurrentExceptionMsg())
  else: socket.connect(url.hostname, port, timeout)
  socket.send(toString(url, metod, headers, body))
  while true:
    let line = socket.recvLine(timeout)
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
      let readLen2 {.used.} = socket.recv(endStr[0].addr, 2, timeout)
      assert endStr == "\r\n"
  else:
    var chunk = newString(contentLength)
    let readLen = socket.recv(chunk[0].addr, contentLength, timeout)
    assert readLen == contentLength
    chunks.add chunk
  when bodyOnly: result = chunks
  else:
    privateAccess url.type
    result = (url: url, metod: metod, isIpv6: url.isIpv6,
              headers: if parseHeader: parseHeaders(res)           else: @[],
              code:    if parseStatus: parseHttpCode(res).HttpCode else: 0.HttpCode,
              body:    if parseBody:   chunks                      else: @[])


runnableExamples"--gc:orc --experimental:strictFuncs -d:ssl -d:nimStressOrc --import:std/httpcore":
  import std/[net, uri]
  let socket: Socket = newSocket()
  doAssert socket.fetch(parseUri"http://httpbin.org/post", HttpPost, body = "data here").code == Http200
  close socket
