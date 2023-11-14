# Medaka HTTP サーバ

## 概要
"Medaka HTTP Server" は Nim 言語で書かれた HTTP サーバである。
この HTTP サーバは Nim の標準ライブラリに含まれる asynchttpserver をベースとしている。
以下では "Medaka HTTP Server" を単に "Medaka" と呼ぶ。

## 機能
Medaka は以下のような機能を持つ。

* HTML ファイルなどの静的なファイルをクライアントへ転送する。
* URL のパスをフックして独自のハンドラを実行する。
* CGI を実行する。(制限あり)
* クッキーを使用可能
* セッション変数を使用可能 (クッキーベース)
* ファイルアップロード
* 様々なリクエスト方法をサポート

### サポートしているリクエスト
* application/x-www-form-urlencoded
* multipart/form-data (FormDataオブジェクトを含む)
* application/json
* application/octed-stream

## インストール
次のようにしてインストールできる。
　git clone https://github.com/makandat/Medaka.git

## ビルド
Medaka フォルダ内で次のコマンドでビルドする。
　build.sh medaka (Linux の場合)
　build.ps1 medaka (Windows の場合)

## 関連ファイル

### 設定ファイル
設定ファイルは medaka.json というファイルである。内容は次のようになっている。
```js
{
  "html":"./html",
  "templates":"./templates",
  "upload":"./upload",
  "cgi-bin":"./cgi-bin"
}
```
* html は静的ファイルの場所である。
* templates はテンプレートファイルの場所である。
* upload はアップロードファイルの保存先である。
* cgi-bin は CGI ファイルの場所である。

### ログファイル
ログファイルは medaka.log という名前である。

### ソースファイル
* medaaka.nim: メインモジュール
* handlers.nim: ルートに対応する各ハンドラ用のモジュール
* body_parser.nim: POST メソッドでのリクエストボディを解析するためのモジュール

## ディレクトリ
* html: HTML ファイルの場所
* html/css: CSS ファイルの場所
* html/js: JavaScript ファイルの場所
* html/img: 画像ファイルの場所
* templates: HTML テンプレートファイルの場所
* bin: ビルド結果の場所
* cgi-bin: CGI ファイルの場所

## カスタマイズ

### medaka.nim
proc callback(req: Request) ではディスパッチ処理を行っている。
ここで req.url.path や req.reqMethod を元に呼び出すべきハンドラを決めて、そのハンドラを呼び出す。
(例)
```nim
#  /hello
if req.url.path == "/hello":
  (status, content, headers) = handlers.get_hello()
```
ハンドラは原則としてタプル (HttpCode, string, HttpHeaders) を返す。
タプルの2番目の要素が HTML などである。

### handlers.nim
ハンドラはタプル (HttpCode, string, HttpHeaders) を返す必要がある。
パラメータについては特に制限はないが、たいていテンプレートファイルのパスやクエリー文字列などを持つ。
ハンドラは非同期メソッド callback からコールされるのでスレッドセーフである必要がある。

## テンプレートファイル
テンプレートファイルは HTML とほぼ同じである。
唯一の違いは、埋め込み文字列を表す {{...}} の部分である。
このカッコ自身とカッコ内のシンボルが外部で与えた文字列で置き換えられる。
次にテンプレートファイルの使用例を示す。
```nim
  var hash = parseQuery(query)
  args["id"] = getQueryValue(hash, "id", "")
  args["title"] = getQueryValue(hash, "title", "")
  args["info"] = getQueryValue(hash, "info", "")
  var (status, buff) = templateFile(filepath, args)
  return (status, buff, htmlHeader())
```


