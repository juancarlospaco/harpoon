# HTTP Harpoon: Clandestine HTTP Client.

- Same API as stdlib `HttpClient`.
- 1 file, 0 dependencies, 300 lines.
- No Curl nor LibCurl dependencies.
- Async and sync client.
- Works with ARC and ORC.
- Works with `strictFuncs`.
- Use `Uri` type for URL.
- `GET` and `POST` from JSON to JSON directly.
- `downloadFile` that takes `openArray` of URLs.
- No unclosed `Socket` bugs, never opens a `Socket`.

