# Medaka server

## Overview
"Medaka HTTP Server" is an HTTP server written in the Nim language.
This HTTP server is based on the asynchttpserver included in Nim's standard library.
In the following, "Medaka HTTP Server" will simply be referred to as "Medaka".

## Function
Medaka has the following functions.

* Transfer static files such as HTML files to the client.
* Hook the path of a URL and run your own handler.
* Run CGI. (with restrictions)
* Cookies allowed
* Session variables available (cookie-based)
* file upload
* Supports various request methods

### Supported requests
* application/x-www-form-urlencoded
* multipart/form-data (contains FormData object)
*application/json
* application/octed-stream

## Install
You can install it as follows.
git clone https://github.com/makandat/Medaka.git

## Build
Build with the following command in the Medaka folder.
build.sh medaka (for Linux)
build.ps1 medaka (for Windows)

## Related files

### Setting file
The configuration file is a file called medaka.json. The contents are as follows.
````js
{
   "html":"./html",
   "templates":"./templates",
   "upload":"./upload",
   "cgi-bin":"./cgi-bin"
}
````
* html is the location of static files.
* templates is the location of template files.
* upload is the save destination for the uploaded file.
* cgi-bin is the location of CGI files.

### logfile
The log file is named medaka.log.

### source file
* medaaka.nim: Main module
* handlers.nim: Module for each handler corresponding to the route
* body_parser.nim: Module for parsing the request body in POST method

## Customization

### medaka.nim
proc callback(req: Request) performs dispatch processing.
Here, decide which handler to call based on req.url.path and req.reqMethod and call that handler.
(example)
```nim
# /hello
if req.url.path == "/hello":
   (status, content, headers) = handlers.get_hello()
````
In principle, the handler returns a tuple (HttpCode, string, HttpHeaders).
The second element of the tuple is HTML, etc.

### handlers.nim
The handler must return a tuple (HttpCode, string, HttpHeaders).
There are no particular restrictions on parameters, but they usually include template file paths, query strings, etc.
The handler is called from the asynchronous method callback, so it must be thread-safe.

## Template file
Template files are almost the same as HTML.
The only difference is the {{...}} part that represents the embedded string.
The parentheses themselves and the symbols inside the parentheses are replaced with the externally supplied string.
An example of how to use a template file is shown below.
```nim
   var hash = parseQuery(query)
   args["id"] = getQueryValue(hash, "id", "")
   args["title"] = getQueryValue(hash, "title", "")
   args["info"] = getQueryValue(hash, "info", "")
   var (status, buff) = templateFile(filepath, args)
   return (status, buff, htmlHeader())
````
