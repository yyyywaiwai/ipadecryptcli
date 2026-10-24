# ipadecrypt

FairDecKitを使ってFairPlay付きIPAを復号するmacOS向けCLIです。
Swift 5.9以降、macOS 12以降に対応します。CLIのヘルプ・プロンプト・独自エラーは英語です。

## ビルド・インストール

```sh
git clone https://github.com/yyyywaiwai/ipadecryptcli.git
cd ipadecryptcli
swift build -c release

mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/ipadecrypt"
BIN_DIR="$(swift build -c release --show-bin-path)"
# Install the resource bundles alongside the executable.
cp "$BIN_DIR/ipadecrypt" "$HOME/.local/lib/ipadecrypt/"
cp -R "$BIN_DIR/"*.bundle "$HOME/.local/lib/ipadecrypt/"
ln -s "$HOME/.local/lib/ipadecrypt/ipadecrypt" "$HOME/.local/bin/ipadecrypt"
export PATH="$HOME/.local/bin:$PATH"
```

シンボリックリンクを既に作成している場合は、`ln -s` の行は再実行不要です。
必要に応じて `PATH` の設定を `~/.zshrc` に追加してください。
実行ファイルを移動するときは、リソースbundleも一緒に移動します。

検証済みのFairDecKitを `Vendor/FairDecKit` に同梱しています。
隣接する別のローカルリポジトリは不要です。ZIP処理の依存先はZIPFoundation 0.9.20です。

## 使い方

```sh
ipadecrypt /path/to/app.ipa -c /path/to/credential.bin
ipadecrypt /path/to/app.ipa --mode lowmem
ipadecrypt /path/to/app.ipa -c /path/to/credential.bin --mode fast
```

### credentialの選択と保存

- `-c` を指定すると、そのファイルを今回の実行でのみ使用します。保存済みcredentialは変更しません。
- `-c` を省略すると、`~/.ipadecrypt/credential.bin` を使用します。
- 保存ファイルがなければ、次のプロンプトを表示します。

```text
Path to credential.bin:
```

入力されたファイルが16バイトであることを確認してから、保存先へコピーします。
元のcredentialは変更しません。保存ディレクトリは権限700、保存ファイルは600です。
空白を含むパスは引用符で囲まずに入力してください。先頭の `~` にも対応します。

空入力・入力終了・読み込み失敗・不正なサイズでは保存せず、エラー終了します。
保存済みcredentialが壊れている場合も自動上書きしません。
`-c` で有効なファイルを指定するか、保存ファイルを手動で退避して再登録してください。
対話入力のない環境では、事前登録するか `-c` を指定します。

credentialは対象IPAに対応した16バイトが必要です。サイズが正しくても、対応しないcredentialでは復号に失敗します。
コピーは復号より先に行うため、復号が失敗しても登録済みcredentialは残ります。

### 処理モード

| オプション | 動作 |
| --- | --- |
| `--mode lowmem` | 既定。バイナリを一時ファイルに展開し、4KiBずつ復号します。 |
| `--mode fast` | バイナリ全体をメモリに読み込み、エントリ用の一時ファイルを省きます。 |

大きなバイナリを `fast` で処理すると、数GiB以上のメモリを使用することがあります。
メモリを抑えたい場合は `lowmem` を使用してください。復号内容は両モードで同じです。

### 出力とZIPの保持

出力は入力と同じディレクトリの `app.decrypted.ipa` です。
入力と既存の出力ファイルは上書きしません。失敗時は不完全なIPAを出力先に公開しません。
成功時の終了コードは0、エラー時は1です。ヘルプは `ipadecrypt --help` で表示します。

ZIPは元のバイト列をコピーし、復号対象の圧縮データと、それに伴うCRC・圧縮サイズ・オフセットだけを更新します。
追加フィールド、エントリ／ZIP全体のコメント、日時、権限、作成元情報、エントリ順は保持します。
未変更エントリは、圧縮データやデータディスクリプターも含めて元のバイト列のままです。

ZIP32のサイズ・オフセットが上限に達する場合は、必要なフィールドだけZIP64へ自動昇格します。
ヘッダーの追加フィールド長、データディスクリプター、後続オフセット、終端レコードも更新し、他の追加フィールドやコメントは保持します。
追加フィールド領域の形式上の上限65,535バイトを超える場合は、既存データを捨てずエラー終了します。

出力先はハードリンク対応のローカルボリュームが必要です。再署名・インストールは行いません。

## テスト

```sh
swift test
swift test --package-path Vendor/FairDecKit
```

CLI引数、credentialの登録・権限・不正入力、入力／出力の保護、合成IPAの既知のSHA-256との一致を検証します。
同梱FairDecKitのテストでは、暗号処理の既知ベクトル、ZIPメタデータ保持、ZIP64昇格も確認します。
実IPA・実credential・生成した大容量データはリポジトリに含めません。

### 4GiB境界をまたぐZIP

```sh
FAIRDECKIT_LARGE_ZIP_TEST=1 \
  swift test -c release --package-path Vendor/FairDecKit --filter ZIP64PromotionTests
```

スパース入力を使い、オフセットが4GiBをまたぐZIPを作成します。
ZIP64への昇格後、ZIPFoundationとmacOSの `unzip -t` で読み出しを確認します。

### 4GiB超の暗号化バイナリ

```sh
swift build -c release
mkdir -p runs

FAIRDECKIT_LARGE_ENCRYPTED_DIR="$PWD/runs/large-encrypted-new" \
FAIRDECKIT_IPADECRYPT_BIN="$(swift build -c release --show-bin-path)/ipadecrypt" \
swift test -c release --package-path Vendor/FairDecKit \
  --filter LargeEncryptedIPATests/testOver4GiBEncryptedBinaryWithInstalledCLI

python3 Tests/verify_large_encrypted.py runs/large-encrypted-new/report.json
```

出力ディレクトリは未作成のパスを指定してください。
生成IPAと復号IPA2個で約12GiBを保存し、処理中はさらに一時ディスク領域が必要です。
`fast` の実行に備え、十分なメモリも確保してください。

テストデータは合成credentialと、1,048,575ページをAES-CBCで暗号化したMach-Oです。
暗号化領域は4,294,963,200バイト、バイナリ全体は4,294,975,488バイト（4GiB＋8KiB）です。
Mach-Oの `cryptsize` は32ビットなので、暗号化領域は最大の4KiB整列値としています。
未暗号化のパディングやZIPのオフセットだけを大きくしたケースではありません。

Python検証では、Swiftの生成バッファを使わず既知の平文を組み立て直し、全バイトのSHA-256、ZIP CRC、メタデータ、両モードの出力IPA全体の一致を確認します。
小さい2ページの生成・復号テストは通常のテストにも含みます。

## 検証実績

2026-10-25、macOS arm64のReleaseビルドで確認しています。

- 実IPA：約258MiB、8バイナリを復号。全12,946エントリの展開後SHA-256・CRC32・サイズが既存Python版と一致。
- 未変更の12,938エントリ：ローカルヘッダー・圧縮データ・データディスクリプターを含め、入力IPAとバイト単位で一致。
- 4GiB超の合成暗号化バイナリ：両モードの全バイトが既知の平文SHA-256と一致。Pythonでも独立に検証済み。

| 合成バイナリの測定 | `lowmem` | `fast` |
| --- | ---: | ---: |
| CLI実行時間 | 約17.73秒 | 約15.40秒 |
| ピークメモリフットプリント | 約51MiB | 約8.12GiB |

メモリ値はmacOSの `/usr/bin/time -l` が報告する `peak memory footprint` です。
いずれも1回ずつの測定で、速度・使用量は入力と実行環境に依存します。
再署名・実機インストール・起動は、この検証には含めていません。
