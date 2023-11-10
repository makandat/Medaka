# medaka_procs.nim
import std/asynchttpserver
import std/[os, strtabs, strformat, strutils, uri, cookies, htmlgen, json, jsonutils, logging, osproc, streams, mimetypes, paths, re, htmlgen]
import db_connector/db_sqlite
import body_parser

const SESSION_NAME* = "medaka_session"

type
  HandlerResult* = (HttpCode, string, HttpHeaders)

func htmlHeader*(): HttpHeaders;
func textHeader*(): HttpHeaders;
func jsonHeader*(): HttpHeaders;
func octedHeader*(): HttpHeaders;

# parse query
func parseQuery*(query: string): StringTableRef =
  result = newStringTable()
  for k, v in decodeQuery(query):
    result[k] = v

# get hash value or default value
func getQueryValue*(hash: StringTableRef, key: string, default: string): string =
  if hash.hasKey(key):
    result = hash[key]
  else:
    result = default

# get posted content-type
func getContentType*(headers: HttpHeaders): string =
  return headers["content-type"]

# parse body (application/x-www-form-urlencoded)
proc parseBody*(body: string): StringTableRef =
  result = newStringTable()
  for k, v in decodeQuery(body):
    result[k] = v

# parse json body (application/json)
proc parseJsonBody*(body: string): JsonNode =
  return parseJson(body)

# parse arraybuffer body (application/octed-stream)
func parseArrayBufferBody*(body: string): string =
  return body  # pure binary data

# parse mulitipart body
func parseMultipartBody*(body: string, headers: HttpHeaders): seq[string] =
  let boundary = body_parser.getBoundary(headers)
  return body_parser.getDispositions(body, boundary)

# parse formdata body (mulitipart/form-data)
func parseFormDataBody*(body: string, headers: HttpHeaders): seq[string] =
  return parseMultipartBody(body, headers)

# return template file as Response
proc templateFile*(filepath: string, args: StringTableRef): (HttpCode, string) =
  try:
    var buff: string = readFile(filepath)
    for k, v in args:
      buff = buff.replace("{{" & k & "}}", v)
    result = (Http200, buff)
  except Exception as e:
    let message = e.msg
    result = (Http500, fmt"<h1>Internal error</h1><p>{message}</p>")

# octed-stream to hex string
proc hexDump*[T](v: T): string =
  var s: seq[uint8] = @[]
  s.setLen(v.sizeof)
  copymem(addr(s[0]), v.unsafeAddr, v.sizeof)
  result = ""
  for i in s:
    result.add(i.toHex)

# get mime type
func getMimetype*(filepath: string): string =
  let m = newMimetypes()
  let p = Path(filepath)
  let (dir, file, ext) = p.splitFile()
  let mime = m.getMimetype(ext)
  return mime

# send file
proc sendFile*(filepath: string, req: Request):HandlerResult  =
  var status: HttpCode = Http200
  var content = ""
  var headers = newHttpHeaders()
  try:
    content = readFile(filepath)
    let mime = getMimetype(filepath)
    headers["Content-Type"] = mime
  except Exception as e:
    error(e.msg)
    status = Http500
    content = fmt"<h1>Fatal error: {e.msg}</h1>"
  return (status, content, headers)

# get StringTable value
func getStValue*(hash: StringTableRef, key:string, default:string=""): string =
  if hash.haskey(key):
    result = hash[key]
  else:
    result = default

# is os Windows
proc is_windows*(): bool =
  return dirExists("C:/Windows")

# getCookies
proc getCookies*(headers: HttpHeaders): StringTableRef =
  var cookies: StringTableRef = newStringTable()
  for k, v in headers:
    if toLowerAscii(k) == "cookie":
      var cookies1 = parseCookies(v)
      for k1, v1 in cookies1:
        cookies[k1] = v1
  return cookies

# setCookieValue
proc setCookieValue*(name, value: string, ret_headers: HttpHeaders): HttpHeaders =
  if name.match(re(r"\w[\w|\d|_]*")):
    var ret_cookies: seq[string] = @[]
    for k, v in ret_headers:
      if k == "Set-Cookie":
        ret_cookies.add(v)
    ret_cookies.add(name & "=" & encodeUrl(value))
    ret_headers["Set-Cookie"] = ret_cookies
  return ret_headers

# removeCookie
proc removeCookie*(name: string, in_headers: HttpHeaders): HttpHeaders =
  var ret_headers = newHttpHeaders()
  if in_headers.hasKey("cookie"):
    var cookie = fmt"{name}=; max-age=0"
    ret_headers["set-cookie"] = cookie
  return ret_headers

# getCookieValue
proc getCookieValue*(name: string, in_headers: HttpHeaders): string =
  var cookies = getCookies(in_headers)
  if len(cookies) == 0:
    return ""
  elif cookies.hasKey(name):
    return decodeUrl(cookies[name])
  else:
    return ""

# getCookieItems
proc getCookieItems*(headers: HttpHeaders): StringTableRef =
  var cookies = getCookies(headers)
  var items = newStringTable()
  for k, v in cookies:
    items[k] = v
  return items

# setSessionValue
proc setSessionValue*(name:string, value:string, headers:HttpHeaders): string =
  if not name.match(re(r"\w[\w|\d|_]*")):
    return ""
  var cookies1: StringTableRef = getCookies(headers)
  var session = ""
  var session_value = ""
  if cookies1.hasKey(SESSION_NAME) and len(cookies1[SESSION_NAME]) > 0:
    session_value = decodeUrl(cookies1[SESSION_NAME])
    var jn: JsonNode = parseJson(session_value)
    jn[name] = % value
    session = $jn
  else:
    session_value = '"' & name & '"' & ':' & '"' & value & '"'
    session = "{" & session_value & "}"
  return session

# getSessionString
proc getSessionString*(headers:HttpHeaders): string =
  var cookies = getCookies(headers)
  var session = decodeUrl(cookies[SESSION_NAME])
  return session

# getSessionValue
proc getSessionValue*(name: string, headers:HttpHeaders): string =
  var session = getSessionString(headers)
  var jn = parseJson(session)
  return $jn[name]

# redirect proc
proc redirect*(url: string): HandlerResult =
  var args = newStringTable()
  args["location"] = url;
  var (status, buff) = templateFile("./templates/redirect.html", args)
  return (status, buff, htmlHeader())

# quote
func q(s: string):string =
  return "\"" & s & "\""

# html header
func htmlHeader*(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"text/html; charset=utf-8"})

# text header
func textHeader*(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"text/plain; charset=utf-8"})

# json header
func jsonHeader*(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"application/json; charset=utf-8"})

# octed-stream header
func octedHeader*(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"application/octed-stream"})


