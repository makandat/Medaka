# Medaka server 
import std/asynchttpserver
import std/asyncdispatch
import std/[files, paths, strtabs, json, mimetypes, strutils, strformat, logging, re]
import handlers

const VERSION = "0.1.5"
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
    error(message)
    result = (Http500, fmt"<h1>Internal error</h1><p>{message}</p>", newHttpHeaders({"Content-Type":"text/html; charset=utf-8"}))

# Callback on Http request
proc callback(req: Request) {.async.} =
  # TODO: 
  info(req.url.path)
  echo req.url.path
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
  #   static files
  if req.reqMethod == HttpGet and fileExists(Path(filepath)):
    (status, content, headers) = staticFile(filepath)
  #  /hello
  elif req.url.path == "/hello":
    (status, content, headers) = handlers.get_hello()
  #  /get_query1
  elif req.url.path == "/get_query1":
    (status, content, headers) = handlers.get_query1(req.url.query)
  #  /get_form1
  elif req.url.path == "/get_form1":
    filepath = templates & "/form1.html"
    (status, content, headers) = handlers.get_form1(filepath, req.url.query)
  #  /post_form2
  elif req.url.path == "/post_form2":
    filepath = templates & "/form2.html"
    (status, content, headers) = handlers.post_form2(filepath, req.headers, req.body)
  #  /post_form3
  elif req.url.path == "/post_form3":
    filepath = templates & "/form3.html"
    (status, content, headers) = handlers.post_form3(filepath, req.headers, "file1", req.body, settings["upload"])
  #  /get_path_param
  elif req.url.path == "/get_path_param" or req.url.path == "/get_path_param/":
    filepath = templates & "/get_path_param.html"
    (status, content, headers) = handlers.get_path_param(filepath, "", req.headers)
  #  /get_path_param regex
  elif match(req.url.path, re(r"\/get_path_param\/\d+")):
    filepath = templates & "/get_path_param.html"
    (status, content, headers) = handlers.get_path_param(filepath, req.url.path, req.headers)
  #  GET /post_request_json
  elif req.reqMethod == HttpGet and req.url.path == "/post_request_json":
    let filepath = htdocs & "/post_request_json.html"
    (status, content, headers) = staticFile(filepath)
  #  POST /post_request_json
  elif req.reqMethod == HttpPost and req.url.path == "/post_request_json":
    (status, content, headers) = handlers.post_request_json(req.body, req.headers)
  #  GET /post_request_formdata
  elif req.reqMethod == HttpGet and req.url.path == "/post_request_formdata":
    filepath = htdocs & "/post_request_formdata.html"
    (status, content, headers) = staticFile(filepath)
  #  POST /post_request_formdata
  elif req.reqMethod == HttpGet and req.url.path == "/post_request_formdata":
    (status, content, headers) = handlers.post_request_formdata(req.body, req.headers)
  #  GET /post_request_arraybuffer
  elif req.url.path == "/post_request_arraybuffer":
    filepath = htdocs & "/post_request_arraybuffer.html"
    (status, content, headers) = staticFile(filepath)
  # POST /post_request_arraybuffer
  elif req.reqMethod == HttpPost and req.url.path == "/post_request_formdata":
    (status, content, headers) = handlers.post_request_formdata(req.body, req.headers)
  #  /redirect
  elif req.url.path == "/redirect":
    filepath = templates & "/redirect.html"
    (status, content, headers) = handlers.get_redirect(req.url.query)
  #  /message
  elif req.url.path == "/message":
    (status, content, headers) = handlers.get_message(req.url.query)
  #  /cookie
  elif req.url.path == "/cookie":
    (status, content, headers) = handlers.get_cookie(req.headers)
  #  /session
  elif req.url.path == "/session":
    filepath = templates & "/session.html"
    (status, content, headers) = handlers.get_session(filepath, req.headers)
  #  /get_medaka_record
  elif req.url.path == "/get_medaka_record":
    if req.url.query == "":
      (status, content, headers) = staticFile("./html/get_medaka_record.html")
    else:
      (status, content, headers) = handlers.get_medaka_record(req.url.query)
  #  /get_medaka_record2
  elif req.url.path == "/get_medaka_record2":
    if req.url.query == "":
      (status, content, headers) = staticFile("./html/get_medaka_record2.html")
    else:
      (status, content, headers) = handlers.get_medaka_record2(req.url.query)
  else:
    status = Http403 # Forbidden
    headers = newHttpHeaders({"Content-Type":"text/html"})
    content = "<h1>Error: This path is fobidden.</h1><p>" & req.url.path & "</p>"
  await req.respond(status, content, headers)

#
#  Start as main
#  =============
when isMainModule:
  initLogger()
  var server = newAsyncHttpServer()
  server.listen(Port(USE_PORT))
  echo START_MSG & "\n http://localhost:" & $USE_PORT
  info START_MSG
  while true:
    if server.shouldAcceptRequest():
      waitFor server.acceptRequest(callback)
    else:
      echo "Sleep"
      waitFor sleepAsync(500)

