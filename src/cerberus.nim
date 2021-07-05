include prelude # TODO: imports

const cacertUrl* = "https://curl.se/ca/cacert.pem"  # cacert.pem URL.

template newDefaultHeaders*(body = ""; userAgent = "x"; contentType = "text/plain"; accept = "*/*"): array[4, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept)]

template newDefaultHeaders*(body = ""; userAgent = "x"; contentType = "text/plain"; accept = "*/*"; proxyUser, proxyPassword: string): array[5, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept), ("Proxy-Authorization", "Basic " & base64.encode(proxyUser & ' ' & proxyPassword))]

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
