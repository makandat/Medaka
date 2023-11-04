if ($args.length -eq 0) {
  "Usage: build.ps1 $1"
  exit
}
$src = $args[0] + ".nim" 
"Compiling $src ..."
nim --hints:off --debugger:native --outdir:bin c $src
if ($LASTEXITCODE -eq 0) {
  $out = "... Saved to './bin/" + $args[0] + ".exe'"
  echo $out
}
else {
  echo "Failed."
}
