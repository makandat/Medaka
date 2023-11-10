# handlers.nim
import std/asynchttpserver
import std/[os, strtabs, strformat, strutils, uri, cookies, htmlgen, json, jsonutils, logging, osproc, streams, mimetypes, paths, re]
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




#
# handlers
#

# hello
proc get_hello*(): HandlerResult =
  result = (Http200, "Hello World!", textHeader())

# execute CGI
proc execCgi*(filepath: string, query: string): (HttpCode, string) =
  let query_string = newStringTable({"QUERY_STRING":query})
  let cgi = startProcess(command=filepath, env=query_string)
  let ostream: Stream = outputStream(cgi)
  let content = ostream.readAll()
  return (Http200, content)


# get_query1
proc get_query1*(query: string): HandlerResult =
  var html = """<!doctype html>
<html>
 <head>
  <meta charset="utf-8">
  <title>query1</title>
 </head>
 <body>
  <h1 style="text-align:center">query1</h1>
  <br />
  <h2 style="text-align:center">{{query}}</h2>
  <p style="text-align:center"><a href="/">HOME</a></p>
 </body>
</html>
"""
  var content = html.replace("{{query}}", query)
  result = (Http200, content, htmlHeader())

# get_form1
proc get_form1*(filepath: string, query: string): HandlerResult=
  var args = newStringTable({"result":query})
  if query == "":
    args["id"] = ""
    args["title"] = ""
    args["info"] = ""
  else:
    var hash = parseQuery(query)
    args["id"] = getQueryValue(hash, "id", "")
    args["title"] = getQueryValue(hash, "title", "")
    args["info"] = getQueryValue(hash, "info", "")
  var (status, buff) = templateFile(filepath, args)
  return (status, buff, htmlHeader())

# post_form2
proc post_form2*(filepath: string, headers:HttpHeaders, body: string): HandlerResult =
  var s = ""
  for k, v in headers:
    s &= k
    s &= ": "
    for w in v:
      s &= w
    s &= "\n"
  var args = newStringTable({"headers":s, "body":body})
  if body == "":
    args["id"] = ""
    args["name"] = ""
    args["age"] = ""
    args["male"] = "checked"
    args["female"] = ""
  else:
    var hash = parseQuery(body)
    args["id"] = getQueryValue(hash, "id", "")
    args["name"] = getQueryValue(hash, "name", "")
    args["age"] = getQueryValue(hash, "age", "")
    if getQueryValue(hash, "male", "") == "male":
      args["male"] = "checked"
      args["female"] = ""
    else:
      args["male"] = ""
      args["female"] = "checked"
  var (status, buff) = templateFile(filepath, args)
  return (status, buff, htmlHeader())

# post_form3
proc post_form3*(filepath: string, headers:HttpHeaders, name: string, body: string, upload_folder:string=""): HandlerResult =
  var s = ""
  for k, v in headers:
    s &= k
    s &= ": "
    for w in v:
      s &= w
    s &= "\n"
  var args = newStringTable({"headers":s, "body":body})
  if body != "":
    var disps = parseMultipartBody(body, headers)
    let savefile = upload_folder & "/" & disps.getFileName(name)
    let chunk = disps.getChunk(name)
    writeFile(savefile, chunk)
  var (status, buff) = templateFile(filepath, args)
  return (status, buff, htmlHeader())

# get_path_param
proc get_path_param*(filepath:string, path:string, headers:HttpHeaders): HandlerResult =
  var s = ""
  var res = ""
  for k, v in headers:
    s &= k
    s &= ": "
    for w in v:
      s &= w
    s &= "\n"
  let parts = path.split("/")
  var id = 0
  if len(parts) > 2:
    id = parseInt(parts[2])
  let db = db_sqlite.open("./medaka.db", "", "", "")
  let sql: SQLQuery = SQLQuery("SELECT * FROM medaka WHERE id = ?")
  var row:Row = db.getRow(sql, id)
  if row[0] == "":
    res = "Empty"
  else:
    for v in row:
      res &= fmt"{v}, "
      res = res.substr(0, len(res)-2)
  var args = newStringTable({"headers":s, "path":path, "result":res})
  var (status, buff) = templateFile(filepath, args)
  return (status, buff, htmlHeader())


# redirecting
proc get_redirect*(query: string): HandlerResult =
  var args = parseQuery(query)
  var (status, buff) = templateFile("./templates/redirect.html", args)
  return (status, buff, htmlHeader())

# show message page
proc get_message*(query: string): HandlerResult =
  var args = parseQuery(query)
  var (status, buff) = templateFile("./templates/message.html", args)
  return (status, buff, htmlHeader())

# cookie
proc get_cookie*(headers: HttpHeaders): HandlerResult =
  var args = newStringTable()
  var cookies: StringTableRef = getCookies(headers)
  var ret_headers = htmlHeader()
  if len(cookies) == 0:
    args["result"] = "クッキーがありません。(初回の場合、リロードしてください。)"
    args["list"] = ""
    ret_headers["Set-Cookie"] = @["a=ABC001", "b=bBBbbB"]
  else:
    args["result"] = "クッキーがあります。"
    args["list"] = ""
    for k, v in cookies:
      args["list"] &= li(fmt"{k}={v}")
  var (status, buff) = templateFile("./templates/cookie.html", args)
  return (status, buff, ret_headers)

# get_medaka_record
proc get_medaka_record*(query: string): HandlerResult =
  var data = parseQuery(query)
  var id = parseInt(getQueryValue(data, "id", "0"))
  let db = db_sqlite.open("./medaka.db", "", "", "")
  var buff: string = ""
  let sql: SQLQuery = SQLQuery("SELECT * FROM medaka WHERE id = ?")
  var row:Row = db.getRow(sql, id)
  if row[0] == "":
    buff = "Empty"
  else:
    for v in row:
      buff &= fmt"{v}, "
      buff = buff.substr(0, len(buff)-2)
  return (Http200, buff, textHeader())
  
# get_medaka_record2
proc get_medaka_record2*(query: string): HandlerResult =
  var data = parseQuery(query)
  var id = parseInt(getQueryValue(data, "id", "0"))
  let db = db_sqlite.open("./medaka.db", "", "", "")
  var j: JsonNode
  let sql: SQLQuery = SQLQuery("SELECT * FROM medaka WHERE id = ?")
  var row:Row = db.getRow(sql, id)
  if row[0] == "":
    j = %* {"id":"", "path":"", "method":"", "query":"", "info":""}
  else:
    j = %* {"id":row[0], "path":row[1], "method":row[2], "query":row[3], "info":row[4]}
  return (Http200, $j, jsonHeader())

# post_request_json
proc post_request_json*(body: string, headers: HttpHeaders): HandlerResult =
  var content = newStringTable()
  var status = Http200
  var res = ""
  var s = ""
  for k, v in headers:
    s &= k
    s &= ": "
    for w in v:
      s &= w
    s &= "\n"
  content["headers"] = s
  content["body"] = body
  content["result"] = ""
  var j = parseJson(body)
  var id = j["id"]
  let db = db_sqlite.open("./medaka.db", "", "", "")
  let sql: SQLQuery = SQLQuery("SELECT * FROM medaka WHERE id = ?")
  var row:Row = db.getRow(sql, id)
  if row[0] == "":
    res = "Empty"
  else:
    for v in row:
      res &= fmt"{v}, "
      res = res.substr(0, len(res)-2)
    content["result"] = res
  var data = %* {"headers":content["headers"], "body":content["body"], "result":content["result"]}
  return (status, $data, jsonHeader())
  
  
# post_request_formdata
proc post_request_formdata*(body: string, headers: HttpHeaders): HandlerResult =
  var status = Http200
  var res = ""
  var s = ""
  for k, v in headers:
    s &= k
    s &= ": "
    for w in v:
      s &= w
    s &= "\n"
  var disps = parseMultipartBody(body, headers)
  var rslt: JsonNode
  var id = disps.getValue("id")
  let path = disps.getValue("path")
  let methods = disps.getValue("methods")
  let query = disps.getValue("query")
  let info = disps.getValue("info")
  var sql: string
  let db = db_sqlite.open("./medaka.db", "", "", "")
  if id == "0":
    # Insert
    sql = "INSERT INTO medaka VALUES(NULL, ?, ?, ?, ?)"
    db.exec(SqlQuery(sql), path, methods, query, info)
    rslt = %* {"result":"Inserted", "headers":s, "body":body}
  else:
    # Update
    sql = "UPDATE medaka SET path=?, methods=?, query=?, info=? WHERE id=?"
    db.exec(SqlQuery(sql), path, methods, query, info, parseInt(id))
    rslt = %* {"result":"Updated", "headers":s, "body":body}
  db.close()
  return (Http200, $rslt, jsonHeader())

# post_request_arraybuffer
proc post_request_arraybuffer*(body: string, headers: HttpHeaders): HandlerResult =
  if headers["content-type"] == "application/octed-stream":
    return (Http200, body, octedHeader())
  raise

# session
proc post_session*(filepath: string, body: string, headers: HttpHeaders): HandlerResult =
  var args = newStringTable()
  var cookies = getCookies(headers)
  var jn:JsonNode = %* {}
  var session = ""
  if cookies.hasKey(SESSION_NAME):
    session = decodeUrl(cookies[SESSION_NAME])
    if session != "":
      try:
        jn = parseJson(session)
      except:
        jn = %* {}
  if body != "":
    var param = parseBody(body)
    let name = param.getStValue("name")
    let value = param.getStValue("value")
    let remove = param.getStValue("remove")
    if remove == "":
      jn[name] = %value
    else:
      jn.delete(name)
    session = encodeUrl($jn)
  var ret_headers: HttpHeaders = htmlHeader()
  ret_headers["Set-Cookie"] = SESSION_NAME & "=" & session
  args["sessionList"] = decodeUrl(session)
  let (status, content) = templateFile(filepath, args)
  return (status, content, ret_headers)

# /cookie_proc
proc cookie_proc*(query:string): (string, HttpHeaders) =
  var kv = parseQuery(query)
  var name = kv["cpname"]
  var value = kv["cpvalue"]
  var ret_headers = textHeader()
  ret_headers = setCookieValue(name, value, ret_headers)
  var content = name & "=" & value
  return (content, ret_headers)

# /session_proc
proc session_proc*(query:string, headers:HttpHeaders): (string, HttpHeaders) =
  var kv = parseQuery(query)
  var ret_headers = newHttpHeaders()
  if kv.hasKey("name") and kv.hasKey("value"):
    var session = setSessionValue(kv["name"], kv["value"], headers)
    ret_headers["Set-Cookie"] = SESSION_NAME & "=" & session.encodeUrl()
    return (session, ret_headers)
  else:
    return ("{\"error\":\"no name\"}", ret_headers)
