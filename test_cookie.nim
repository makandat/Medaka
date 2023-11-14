# test procs of cookie and session
import std/[asynchttpserver, uri, strtabs, strformat]
import handlers, medaka_procs

# proc getCookies(headers: HttpHeaders): StringTableRef
block:
  echo "** getCookies(headers: HttpHeaders): StringTableRef"
  var headers = newHttpHeaders({"cookie":"a=AAA; b=bb; xx=XXXX", "content-type":"application/json"})
  var cookies = medaka_procs.getCookies(headers)
  for k in cookies.keys:
    echo k, ":", cookies[k]

# proc setCookieValue*(name, value: string, headers: HttpHeaders): HttpHeaders =
block:
  echo "** setCookieValue*(name, value: string)"
  var headers = newHttpHeaders()
  var ret_headers = htmlHeader()
  headers = setCookieValue("option", "OPTION", ret_headers)
  ret_headers = headers
  headers = setCookieValue("site", "SITES", ret_headers)
  for k, v in headers.pairs:
    echo k, ":", v

# proc removeCookie*(name: string, headers: HttpHeaders): HttpHeaders =
block:
  echo "** removeCookie*(name: string, headers: HttpHeaders): HttpHeaders"
  var headers = newHttpHeaders({"cookie":"a=AAA; b=bb; xx=XXXX", "content-type":"application/json"})
  var ret_headers = removeCookie("xx", headers)
  for k, v in ret_headers.pairs:
    echo k, ":", v

# proc getCookieValue*(name: string, headers: HttpHeaders): string =
block:
  echo "** proc getCookieValue*(name: string, headers: HttpHeaders): string ="
  var headers = newHttpHeaders({"cookie":"a=AAA; b=bb; xx=XXXX", "content-type":"application/json"})
  var cookie_value = getCookieValue("a",headers)
  echo cookie_value
  cookie_value = getCookieValue("b",headers)
  echo cookie_value

# proc getCookieItems*(headers: HttpHeaders): StringTableRef =
block:
  echo "** proc getCookieItems*(headers: HttpHeaders): StringTableRef ="
  var headers = newHttpHeaders({"cookie":"a=AAA; b=bb; xx=XXXX", "content-type":"application/json"})
  var cookielist = getCookieItems(headers)
  for k, v in cookielist.pairs:
    echo fmt"{k}={v}"


# proc setSessionValue*(name:string, value:string, headers:HttpHeaders) =
block:
  echo "\n** proc setSessionValue*(name:string, value:string, headers:HttpHeaders) ="
  var headers = newHttpHeaders()
  var session = setSessionValue("x1", "0.5", headers)
  echo session
  headers["cookie"] = session
  session = setSessionValue("y1", "5.0", headers)
  echo session

# proc getSessionValue*(name: string, headers:HttpHeaders): string =
block:
  echo "** proc getSessionValue*(name: string, headers:HttpHeaders): string ="
  var session = SESSION_NAME & "=" & "{\"x\":\"1.2\", \"y\":\"0.3\"}".encodeUrl()
  var headers = newHttpHeaders({"cookie":session})
  echo getSessionValue("x", headers)
  echo getSessionValue("y", headers)

# proc getSessionString*(headers:HttpHeaders): string =
block:
  echo "** proc getSessionString*(headers:HttpHeaders): string ="
  var headers = newHttpHeaders()
  var session = setSessionValue("x", "2.5", headers)
  headers["cookie"] = SESSION_NAME & "=" & session
  echo getSessionString(headers)

# proc cookie_proc*(query:string, headers:HttpHeaders): string =
block:
  echo "\n** proc cookie_proc*(query:string, headers:HttpHeaders): string ="
  var query = "cpname=option&cpvalue=XXXXXX"
  var content = ""
  var ret_headers = newHttpHeaders()
  (content, ret_headers) = cookie_proc(query)
  echo content
  for k, v in ret_headers.pairs:
    echo k, ": ", v

# proc session_proc*(query:string, headers:HttpHeaders): string =
block:
  echo "** proc session_proc*(query:string, headers:HttpHeaders): string ="
  var query = "name=x&value=9"
  var headers = newHttpHeaders({"cookie":"medaka_session={\"L\":\"QQQ\", \"R\":\"657\"}"})
  var content = ""
  var ret_headers = newHttpHeaders()
  (content, ret_headers) = session_proc(query, headers)
  echo content
  for k, v in ret_headers.pairs:
    echo k, ":", v
