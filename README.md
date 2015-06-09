nsmgmt
======

Description
-----------

- 編集したゾーンファイルの検知し SOA のシリアル値を自動更新
- サーバ毎に定義されたタスクを実行

Requirements
------------

- bash (4.x.x)
- gawk
  - gawk or awk
- findutils
  - find, xargs
- coreutils
  - basename, cat, comm, cp, cut, dirname, ls, rm, sha256sum, sort, touch

Install
-------

### 必要コマンドインストール

```
# yum install bash coreutils findutils gawk
```

### 任意のディレクトリに clone

```
$ git clone https://github.com/directorz/nsmgmt.git
```

### 設定ファイルひな形のコピー

```
$ cd nsmgmt/etc
$ cp -a nsmgmt.conf.sample nsmgmt.conf
```

Configuration
-------------

### メイン設定: `nsmgmt.conf`

オプション | 値の範囲 | デフォルト値 | 必須 | 説明
:----------|:---------|:-------------|------|:----
zones_src_path | - | - | yes | ユーザが編集するゾーンファイルのディレクトリ (絶対パスまたは nsmgmt.conf からの相対パス)
zones_dst_path | - | - | yes | ゾーンファイルの出力先 (絶対パスまたは nsmgmt.conf からの相対パス)
update_serial | 0,1 | 1 | no | ゾーンファイルの出力時に SOA のシリアル値を更新するかどうか (0:しない, 1:する)
update_serial_cmdline | - | cat | no | SOA のシリアル値を更新するためのコマンドライン (標準入力に更新前のゾーンファイルの内容が与えられる)
tasks | - | () | no | ゾーンファイルに変更が合った場合に実行されるコマンドラインの配列 (コンフィグの生成やサーバのリロード等)
pre_process_cmdline | - | "" | no | 処理前に実行するコマンドライン (0 以外で終了すると続く処理を行わない)
post_process_cmdline | - | "" | no | 処理後に実行するコマンドライン

Usage
-----

- `nsmgmt -h` を参照

Licence
-------

[MIT License](LICENSE)
