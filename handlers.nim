# handlers.nim
import std/asynchttpserver
import std/[strtabs, strformat, strutils, uri, cookies, htmlgen, logging]
import db_connector/db_sqlite

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

# parse body
func parseBody(body: string): StringTableRef =
  result = newStringTable()

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

# html header
func htmlHeader(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"text/html; charset=utf-8"})

# text header
func textHeader(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"text/plain; charset=utf-8"})

# json header
func jsonHeader(): HttpHeaders =
  return newHttpHeaders({"Content-Type":"application/json; charset=utf-8"})


#
# handlers
#

# hello
proc get_hello*(): (HttpCode, string, HttpHeaders) =
  result = (Http200, "Hello World!", newHttpHeaders({"Content-Type":"text/plain"}))

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
proc post_form2*(filepath: string, body: string): (HttpCode, string, HttpHeaders) =
  var args = newStringTable({"result":body})
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
proc post_form3*(filepath: string, body: string): (HttpCode, string, HttpHeaders) =
  var args = newStringTable({"result":body})
  if body != "":
    var hash = parseBody(body)
  var (status, buff) = templateFile(filepath, args)
  return (status, buff, htmlHeader())

# redirecting
proc get_redirect*(query: string): (HttpCode, string, HttpHeaders) =
  info("get_redirect: " & query)
  var args = parseQuery(query)
  var (status, buff) = templateFile("./templates/redirect.html", args)
  return (status, buff, htmlHeader())

# show message page
proc get_message*(query: string): (HttpCode, string, HttpHeaders) =
  info("get_message: " & query)
  var args = parseQuery(query)
  var (status, buff) = templateFile("./templates/message.html", args)
  return (status, buff, htmlHeader())

# cookie
proc get_cookie*(headers: HttpHeaders): (HttpCode, string, HttpHeaders) =
  info("get_cookie")
  var args = newStringTable()
  var i = 0
  var cookies: StringTableRef
  for k, v in headers:
    if toLowerAscii(k) == "cookie":
      i += 1
      cookies = parseCookies(v)
  var h = htmlHeader()
  if i == 0:
    args["result"] = "クッキーがありません。(初回の場合、リロードしてください。)"
    args["list"] = ""
    h["Set-Cookie"] = @["a=ABC", "b=bBBB"]
  else:
    args["result"] = "クッキーがあります。"
    args["list"] = ""
    for k, v in cookies:
      args["list"] &= li(fmt"{k}={v}")
  var (status, buff) = templateFile("./templates/cookie.html", args)
  return (status, buff, h)

# get_medaka_record
proc get_medaka_record*(query: string): (HttpCode, string, HttpHeaders) =
  info("get_medaka_record: " & query)
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
      buff &= string(v)
      buff &= ","
      buff = buff.substr(0, len(buff)-2)
  return (Http200, buff, textHeader())
  
# get_medaka_record2
proc get_medaka_record2*(query: string): (HttpCode, string, HttpHeaders) =
  info("get_medaka_record2: " & query)
  var data = parseQuery(query)
  var id = parseInt(getQueryValue(data, "id", "0"))
  let db = db_sqlite.open("./medaka.db", "", "", "")
  var buff: string = ""
  let sql: SQLQuery = SQLQuery("SELECT * FROM medaka WHERE id = ?")
  var row:Row = db.getRow(sql, id)
  if row[0] == "":
    buff = "{\"id\":\"\", \"path\":\"\", \"method\":\"\", \"query\":\"\", \"info\":\"\"}"
  else:
    buff = "{\"id\":"
    buff &= $row[0]
    buff &= ", \"path\":\""
    buff &= row[1]
    buff &= "\", \"method\":\""
    buff &= row[2]
    buff &= "\", \"query\":\""
    buff &= row[3]
    buff &= "\", \"info\":\""
    buff &= row[4]
    buff &= "\"}"
  return (Http200, buff, jsonHeader())
