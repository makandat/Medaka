# handlers.nim
import std/asynchttpserver
import std/[strtabs, strformat, strutils, uri, cookies, htmlgen, json, jsonutils, logging, osproc, streams]
import db_connector/db_sqlite
import body_parser

const SESSION_NAME = "medaka_session"

type BodyState = enum
  Boundary
  Disportion
  Data

# parse query
func parseQuery(query: string): StringTableRef =
  result = newStringTable()
  for k, v in decodeQuery(query):
    result[k] = v

# get hash value or default value
func getQueryValue(hash: StringTableRef, key: string, default: string): string =
  if hash.hasKey(key):
    result = hash[key]
  else:
    result = default

# get posted content-type
func getContentType(headers: HttpHeaders): string =
  return headers["content-type"]

# parse body (application/x-www-form-urlencoded)
proc parseBody(body: string): StringTableRef =
  result = newStringTable()
  for k, v in decodeQuery(body):
    result[k] = v

# parse json body (application/json)
proc parseJsonBody(body: string): JsonNode =
  return parseJson(body)

# parse arraybuffer body (application/octed-stream)
func parseArrayBufferBody(body: string): string =
  return body  # pure binary data

# parse mulitipart body
func parseMultipartBody(body: string, headers: HttpHeaders): seq[string] =
  let boundary = body_parser.getBoundary(headers)
  return body_parser.getDispositions(body, boundary)

# parse formdata body (mulitipart/form-data)
func parseFormDataBody(body: string, headers: HttpHeaders): seq[string] =
  return parseMultipartBody(body, headers)

# return template file as Response
proc templateFile(filepath: string, args: StringTableRef): (HttpCode, string) =
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

# get cookies
proc getCookies(headers: HttpHeaders): StringTableRef =
  var cookies: StringTableRef = newStringTable()
  for k, v in headers:
    if toLowerAscii(k) == "cookie":
      var cookies1 = parseCookies(v)
      for k1, v1 in cookies1:
        cookies[k1] = v1
  return cookies


# get StringTable value
func getStValue(hash: StringTableRef, key:string, default:string=""): string =
  if hash.haskey(key):
    result = hash[key]
  else:
    result = default

# html header
func htmlHeader(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"text/html; charset=utf-8"})

# text header
func textHeader(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"text/plain; charset=utf-8"})

# json header
func jsonHeader(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"application/json; charset=utf-8"})

# octed-stream header
func octedHeader(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"application/octed-stream"})




#
# handlers
#

# hello
proc get_hello*(): (HttpCode, string, HttpHeaders) =
  result = (Http200, "Hello World!", newHttpHeaders({"Content-Type":"text/plain"}))

# execute CGI
proc execCgi*(filepath: string, query: string): (HttpCode, string) =
  let query_string = newStringTable({"QUERY_STRING":query})
  let cgi = startProcess(command=filepath, env=query_string)
  let ostream: Stream = outputStream(cgi)
  let content = ostream.readAll()
  return (Http200, content)


# get_query1
proc get_query1*(query: string): (HttpCode, string, HttpHeaders) =
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
proc get_form1*(filepath: string, query: string): (HttpCode, string, HttpHeaders) =
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
proc post_form2*(filepath: string, headers:HttpHeaders, body: string): (HttpCode, string, HttpHeaders) =
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
proc post_form3*(filepath: string, headers:HttpHeaders, name: string, body: string, upload_folder:string=""): (HttpCode, string, HttpHeaders) =
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
proc get_path_param*(filepath:string, path:string, headers:HttpHeaders): (HttpCode, string, HttpHeaders) =
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
proc get_redirect*(query: string): (HttpCode, string, HttpHeaders) =
  var args = parseQuery(query)
  var (status, buff) = templateFile("./templates/redirect.html", args)
  return (status, buff, htmlHeader())

# show message page
proc get_message*(query: string): (HttpCode, string, HttpHeaders) =
  var args = parseQuery(query)
  var (status, buff) = templateFile("./templates/message.html", args)
  return (status, buff, htmlHeader())

# cookie
proc get_cookie*(headers: HttpHeaders): (HttpCode, string, HttpHeaders) =
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
proc get_medaka_record*(query: string): (HttpCode, string, HttpHeaders) =
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
proc get_medaka_record2*(query: string): (HttpCode, string, HttpHeaders) =
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
proc post_request_json*(body: string, headers: HttpHeaders): (HttpCode, string, HttpHeaders) =
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
proc post_request_formdata*(body: string, headers: HttpHeaders): (HttpCode, string, HttpHeaders) =
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
proc post_request_arraybuffer*(body: string, headers: HttpHeaders): (HttpCode, string, HttpHeaders) =
  if headers["content-type"] == "application/octed-stream":
    return (Http200, body, octedHeader())
  raise

# session
proc post_session*(filepath: string, body: string, headers: HttpHeaders): (HttpCode, string, HttpHeaders) =
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
