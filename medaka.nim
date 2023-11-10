# Medaka server 
import std/asynchttpserver
import std/asyncdispatch
import std/[files, paths, strtabs, json, mimetypes, strutils, strformat, logging, re]
import handlers

const VERSION = "0.3.3"
const USE_PORT:uint16 = 2024
const CONFIG_FILE = "medaka.json"
const LOG_FILE = "medaka.log"
let START_MSG = fmt"Start medaka server v{VERSION} ..."

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
  # CGI
  elif req.reqMethod == HttpGet and req.url.path.startsWith("/cgi-bin/"):
    if handlers.is_windows():
      content = "<h1>CGI is not supported on Windows.</h1>"
      status = Http400
    else:
      try:
        filepath = settings["cgi-bin"] & "/" & req.url.path.substr(len("/cgi-bin/"))
        (status, content) = handlers.execCgi(filepath, req.url.query)
        headers = newHttpHeaders()
        var lines = content.split("\n")
        var i = 0
        while len(lines[i]) > 0:
          var pair = lines[i].split(": ")
          headers[pair[0]] = pair[1]
          i += 1
        content = ""
        i += 1
        while i < len(lines):
          content &= lines[i] & "\n"
          i += 1
      except Exception as e:
        content = e.msg
    await req.respond(status, content, headers)
    return
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
    (status, content, headers) = handlers.post_request_arraybuffer(req.body, req.headers)
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
  #  /remove_cookies
  elif req.url.path == "/remove_cookie":
    let filepath = htdocs & "/remove_cookie.html"
    (status, content, headers) = staticFile(filepath)
  #  /session
  elif req.reqMethod == HttpGet and req.url.path == "/session":
    echo req.headers
    filepath = templates & "/session.html"
    (status, content, headers) = handlers.post_session(filepath, req.url.query, req.headers)
  elif req.reqMethod == HttpPost and req.url.path == "/session":
    filepath = templates & "/session.html"
    (status, content, headers) = handlers.post_session(filepath, req.body, req.headers)
  #  /get_medaka_record
  elif req.url.path == "/get_medaka_record":
    if req.url.query == "":
      (status, content, headers) = staticFile("./html/get_medaka_record.html")
    else:
      (status, content, headers) = handlers.get_medaka_record(req.url.query)
  #  /get_medaka_record2
  elif req.url.path == "/get_medaka_record2":
    if req.url.query == "":
      filepath = htdocs & "/get_medaka_record2.html"
      (status, content, headers) = staticFile(filepath)
    else:
      (status, content, headers) = handlers.get_medaka_record2(req.url.query)
  # /jump (redirect)
  elif req.url.path == "/jump":
    let kv = handlers.parseQuery(req.url.query)
    (status, content, headers) =  handlers.redirect(kv["url"])
  # /cookie_proc
  elif req.url.path == "/cookie_proc":
    headers = textHeader()
    (content, headers) = handlers.cookie_proc(req.url.query)
  # /session_proc
  elif req.url.path == "/session_proc":
    headers = jsonHeader()
    (content, headers) = handlers.session_proc(req.url.query, req.headers)
  # /sendfile
  elif req.url.path == "/sendfile":
    var kv = parseQuery(req.url.query)
    let filepath = kv["path"]
    (status, content, headers) = handlers.sendfile(filepath, req)
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
  echo START_MSG & "\n URL: http://localhost:" & $USE_PORT
  info START_MSG
  while true:
    if server.shouldAcceptRequest():
      waitFor server.acceptRequest(callback)
    else:
      echo "Sleep"
      waitFor sleepAsync(500)

