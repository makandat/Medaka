# Medaka server 
import std/asynchttpserver
import std/asyncdispatch
import std/[files, paths, strtabs, json, mimetypes, strutils, strformat, logging]
import handlers

const VERSION = "0.1.3"
const USE_PORT:uint16 = 2024
const CONFIG_FILE = "medaka.json"
const LOG_FILE = "medaka.log"
const START_MSG = "Start medaka server ..."

# read medaka.json
proc readSettings(): StringTableRef =
  let settings = newStringTable()
  let s = readFile(CONFIG_FILE)
  let data = parseJson(s)
  for x in data.pairs:
    settings[x.key] = x.val.getStr("")
  return settings

# initialize logger
proc initLogger() =
  let file = open(LOG_FILE, fmAppend)
  let logger = newFileLogger(file, fmtStr=verboseFmtStr)
  addHandler(logger)

# return static file as Response
proc staticFile(filepath: string): (HttpCode, string, HttpHeaders) =
  try:
    let (dir, name, ext) = splitFile(Path(filepath))
    let m = newMimeTypes()
    var mime = m.getMimeType(ext)
    if ext == ".txt" or ext == ".html":
      mime = mime & "; charset=utf-8"
    var buff: string = readFile(filepath)
    result = (Http200, buff, newHttpHeaders({"Content-Type":mime}))
  except Exception as e:
    let message = e.msg
    result = (Http500, fmt"<h1>Internal error</h1><p>{message}</p>", newHttpHeaders({"Content-Type":"text/html; charset=utf-8"}))

# Callback on Http request
proc callback(req: Request) {.async.} =
  # TODO: 
  var status = Http200
  var content = ""
  var headers = newHttpHeaders({"Content-Type":"text/html; charset=utf-8"})
  let settings = readSettings()
  var filepath = ""
  let htdocs = settings["html"]
  let templates = settings["templates"]
  if req.url.path == "" or req.url.path == "/":
    filepath = htdocs & "/index.html"
  else:
    filepath = htdocs & "/" & req.url.path
  # dispatch handler by method and path
  if req.reqMethod == HttpGet and fileExists(Path(filepath)):
    (status, content, headers) = staticFile(filepath)
  elif req.url.path == "/hello":
    (status, content, headers) = handlers.get_hello()
  elif req.url.path == "/get_query1":
    (status, content, headers) = handlers.get_query1(req.url.query)
  elif req.url.path == "/get_form1":
    filepath = templates & "/form1.html"
    (status, content, headers) = handlers.get_form1(filepath, req.url.query)
  elif req.url.path == "/post_form2":
    filepath = templates & "/form2.html"
    (status, content, headers) = handlers.post_form2(filepath, req.body)
  elif req.url.path == "/post_form3":
    filepath = templates & "/form3.html"
    (status, content, headers) = handlers.post_form3(filepath, req.body)
  elif req.url.path == "/redirect":
    filepath = templates & "/redirect.html"
    (status, content, headers) = handlers.get_redirect(req.url.query)
  elif req.url.path == "/message":
    (status, content, headers) = handlers.get_message(req.url.query)
  elif req.url.path == "/cookie":
    (status, content, headers) = handlers.get_cookie(req.headers)
  elif req.url.path == "/get_medaka_record":
    if req.url.query == "":
      (status, content, headers) = staticFile("./html/get_medaka_record.html")
    else:
      (status, content, headers) = handlers.get_medaka_record(req.url.query)
  elif req.url.path == "/get_medaka_record2":
    if req.url.query == "":
      (status, content, headers) = staticFile("./html/get_medaka_record2.html")
    else:
      (status, content, headers) = handlers.get_medaka_record2(req.url.query)
  else:
    status = Http403 # Forbidden
    content = "<h1>Error: This path is fobidden.</h1><p>" & req.url.path & "</p>"
  await req.respond(status, content, headers)

#
#  Start as main
#  =============
when isMainModule:
  initLogger()
  var server = newAsyncHttpServer()
  server.listen(Port(USE_PORT))
  echo START_MSG
  info START_MSG
  while true:
    if server.shouldAcceptRequest():
      echo "Accept"
      waitFor server.acceptRequest(callback)
    else:
      echo "Sleep"
      waitFor sleepAsync(500)

