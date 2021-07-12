import std/[httpclient, uri]
import benchy, puppy, harpoon

timeIt "HTTP Harpoon  ":
  discard getContent(parseUri"http://127.0.0.1/")

timeIt "std/httpclient":
  let client = newHttpClient()
  discard client.getContent"http://127.0.0.1/"
  client.close()

timeIt "Puppy         ":
  discard fetch"http://127.0.0.1/"
