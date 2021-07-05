import base64

const cacertUrl* = "https://curl.se/ca/cacert.pem"  # cacert.pem URL.

template newDefaultHeaders*(body = ""; userAgent = "x"; contentType = "text/plain"; accept = "*/*"): array[4, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept)]

template newDefaultHeaders*(body = ""; userAgent = "x"; contentType = "text/plain"; accept = "*/*"; proxyUser, proxyPassword: string): array[5, (string, string)] =
  [("Content-Length", $body.len), ("User-Agent", userAgent), ("Content-Type", contentType), ("Accept", accept), ("Proxy-Authorization", "Basic " & base64.encode(proxyUser & ' ' & proxyPassword))]
