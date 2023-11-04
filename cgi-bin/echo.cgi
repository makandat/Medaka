#!/usr/bin/env python3
import os, urllib.parse

print("Content-Type: text/html\n")

query_string = os.getenv("QUERY_STRING")
pair = query_string.split("=")
print("<h1>")
print(pair[0] + "=" + urllib.parse.unquote(pair[1]))
print("</h1>")

