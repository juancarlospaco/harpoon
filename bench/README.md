# Benchmarks

- x86_64, Bedrock Linux, Offline, Nim devel, 2021.

```nim
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
```


```console
$ nim r -f -d:ssl --gc:orc bencho_stdlib.nim

HTTP Harpoon    736 microseconds and 45 nanoseconds
std/httpclient  19 milliseconds, 729 microseconds, and 352 nanoseconds
Puppy
Traceback (most recent call last)
bencho_stdlib.nim(19) bencho_stdlib
puppy.nim(196) fetch
SIGSEGV: Illegal storage access. (Attempt to read from nil?)


$ nim r -f -d:ssl --gc:arc bencho_stdlib.nim

HTTP Harpoon    708 microseconds and 794 nanoseconds
std/httpclient  21 milliseconds, 209 microseconds, and 649 nanoseconds
Puppy
Traceback (most recent call last)
bencho_stdlib.nim(19) bencho_stdlib
puppy.nim(196) fetch
SIGSEGV: Illegal storage access. (Attempt to read from nil?)


$ nim r -f -d:ssl -d:release bencho_stdlib.nim

HTTP Harpoon    453 microseconds and 589 nanoseconds
std/httpclient  14 milliseconds, 983 microseconds, and 833 nanoseconds
Puppy
*** stack smashing detected ***: terminated.
SIGABRT: Abnormal termination.


$ nim r -f -d:ssl -d:danger bencho_stdlib.nim

HTTP Harpoon    553 microseconds and 25 nanoseconds
std/httpclient  15 milliseconds, 45 microseconds, and 642 nanoseconds
Puppy
*** stack smashing detected ***: terminated
SIGABRT: Abnormal termination.


$ nim r -f -d:ssl --gc:orc bencho_benchy.nim

name ............................... min time      avg time    std dv   runs
HTTP Harpoon   ..................... 0.110 ms      0.142 ms    ±0.027  x1000
std/httpclient ..................... 0.150 ms      0.169 ms    ±0.043  x1000
Puppy
Traceback (most recent call last)
benchy.nim(83) bencho_benchy
bencho_benchy.nim(13) test
puppy.nim(196) fetch
SIGSEGV: Illegal storage access. (Attempt to read from nil?)
```
