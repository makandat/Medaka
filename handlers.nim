#
# handlers.nim
#
import medaka_procs
import std/asynchttpserver
import std/[os, strtabs, strformat, strutils, uri, cookies, htmlgen, json, jsonutils, logging, osproc, streams, mimetypes, paths, re, htmlgen]
import db_connector/db_sqlite
import body_parser

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

# /medaka_db
proc medaka_db*(`template`: string): string =
  var args = newStringTable()
  let db = db_sqlite.open("./medaka.db", "", "", "")
  var medaka_table = ""
  for x in db.fastRows(sql"SELECT * FROM medaka"):
    var row = ""
    row = tr(td(x[0]) & td(x[1]) & td(x[2]) & td(x[3]) & td(x[4]))
    medaka_table &= row
  args["medaka_table"] = medaka_table
  var nimble_table = ""
  for x in db.fastRows(sql"SELECT * FROM nimble"):
    var row = ""
    row = tr(td(x[0]) & td(x[1]) & td(x[2]) & td(x[3]))
    nimble_table &= row
  args["nimble_table"] = nimble_table
  let filepath = `template` & "/medaka_db.html"
  return templateFile(filepath, args)[1]
