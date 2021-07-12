import std/[httpclient, times, uri]
import puppy, harpoon

template timeIt(s: static[string]; code) =
  block:
    let t = now()
    code
    echo s, '\t', now() - t

timeIt "HTTP Harpoon  ":
  discard getContent(parseUri"http://127.0.0.1/")

timeIt "std/httpclient":
  let client = newHttpClient()
  discard client.getContent"http://127.0.0.1/"
  client.close()

timeIt "Puppy         ":
  discard fetch"http://127.0.0.1/"
