# fairdeckit

FairPlay付きIPAと16バイトのcredentialから、復号済みIPAまたはarm64バイナリを返すSwift Packageです。iOS/macOSアプリに組み込めます。

`decrypt.py`、`core.py`、`transform.c`の復号処理をSwiftに移植しています。Python・C実行ファイル・外部プロセス・ネットワーク接続は実行時に使いません。AES-CBCはCommonCrypto、MD5はCryptoKit、ZIP処理は[ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.20以降を使います。変換テーブルはSPMリソースに含まれます。

credentialの取得は既存の[Pythonスクリプト](https://github.com/EthanArbuckle/fairplay-decrypt/blob/main/credential-retrieval/README.md)で行います。

## アプリから使う

Xcodeで`FairDecKit`ディレクトリをローカルSwift Packageとして追加し、`FairDecKit` productをアプリのtargetに組み込みます。Swift tools 5.9以降、iOS 15以降、macOS 12以降が対象です。

### IPAを復号する

```swift
import Foundation
import FairDecKit

func decryptIPA(input: URL, output: URL, credentialFile: URL, mode: FairDecKit.Mode = .lowMemory) async throws -> URL {
    let credential = try Data(contentsOf: credentialFile)
    return try await Task.detached(priority: .userInitiated) {
        try FairDecKit.decryptIPA(at: input, to: output, credential: credential, mode: mode)
    }.value
}
```

`input`、`output`にはローカルのファイルURLを渡します。出力先にはハードリンクを使えるファイルシステムが必要です。出力先が既にある場合はエラーになり、入力IPAと既存の出力ファイルは上書きしません。新しい出力先ディレクトリは復号に失敗しても残ることがあります。途中で失敗した場合は一時IPAを削除し、出力先には公開しません。

ZIPは元のバイト列をコピーし、復号対象の圧縮データと、それに伴うCRC・圧縮サイズ・参照オフセットだけを書き換えます。
ローカル／中央ヘッダーの追加フィールド、エントリコメント、ZIP全体のコメント、日時、権限、作成元情報、ファイル名の元のエンコーディング、エントリ順は保持します。
ZIP64追加フィールドのサイズ・オフセットなど、データ変更に依存する数値だけは更新します。
未変更エントリは圧縮データやデータディスクリプターも含めてそのままコピーし、再圧縮しません。日時が無効な値でも正規化しません。
APIは同期処理です。アプリでは上の例のようにメインアクターの外で呼び出してください。

### 処理モードを選ぶ

`decryptIPA`と`decryptBinaries`は`mode: FairDecKit.Mode`を受け取ります。省略時は`.lowMemory`です。

| モード | 処理方法 | 向いている用途 |
| --- | --- | --- |
| `.lowMemory` | 一時ファイルへ分割展開し、4KBずつ復号 | iOSや大きいIPAなど、メモリを抑えたい場合 |
| `.fast` | エントリ全体をメモリに読み、エントリ用の一時ファイルを使わず処理 | メモリに余裕があり、ディスクI/Oを減らしたい場合 |

```swift
try FairDecKit.decryptIPA(at: inputURL, to: outputURL, credential: credential, mode: .fast)
```

両モードとも、入力・既存出力の保護、CRC/サイズ検証、出力権限、復号する内容は同じです。`.fast`でもIPAの出力は非公開の一時IPAへ書き、成功後に公開します。大きなバイナリでは暗号化データと復号結果の両方を保持するため、数百MB以上を使います。

### IPAからバイナリだけを取り出す

```swift
let binaries: [String: Data] = try FairDecKit.decryptBinaries(in: inputURL, credential: credential, mode: .lowMemory)
```

辞書のキーはIPA内のパス、値は復号済みMach-Oです。本体・拡張機能・Frameworkをまとめて返し、IPAファイルは書き出しません。`.lowMemory`では復号中の暗号化バイナリを全体バッファに保持しませんが、両モードとも返すバイナリはすべて`Data`としてメモリに保持します。

### Mach-Oを直接渡す

```swift
import Foundation
import FairDecKit

func decryptBinary(binary: Data, sinf: Data, supf: Data, credential: Data) throws -> Data {
    try FairDecKit.decryptBinary(binary, sinf: sinf, supf: supf, credential: credential)
}
```

このAPIは既にメモリ上にある`Data`を受け取るため、モード指定はありません。

`binary`はMach-O全体、`sinf`と`supf`は対応する`SC_Info`ファイルの内容です。IPA APIは`.v5.supf`を優先し、対応する`.v4.sinf`、通常の`.sinf`、親appのSINFの順でこれらのレコードを自動で選択します。`cryptid == 0`のバイナリはIPA内ではそのまま残し、バイナリ単体APIでは`FairDecKitError.notEncrypted`になります。

## 対応形式と制限

- thin／FAT32／FAT64 Mach-Oのarm64スライス。arm64スライスは1つ、暗号化ページは4,096バイト、`cryptid == 1`が対象です。他アーキテクチャのスライスは変更しません。
- version 3／5のSUPF（識別子`507`、`510`、`612`）。arm64 subtype 0のレコードを扱います。
- 448バイト、または末尾8バイトがゼロの440バイトSINF `priv`レコード。
- credentialはそのIPAに対応した16バイトが必要です。別アカウント等のcredentialはSINF検証エラーになります。

`.lowMemory`のIPA出力では復号対象のバイナリを非公開の一時ファイルへ64KBずつ展開し、暗号領域を4KBずつ復号します。
バイナリ全体の入力・出力バッファは保持しません。未変更エントリもCRC・サイズ検証を行ってから元の圧縮バイト列をコピーします。
SINF/SUPFとZIPのメタデータはメモリに保持するため、使用量はこれらのサイズにも依存します。
両モードとも、復号対象の再圧縮データを一時ZIPに保持します。`.lowMemory`ではさらに最大の復号対象バイナリ程度の一時領域が必要です。
シンボリックリンクの内容は64KBまでです。通常のファイルと異なりZIPFoundationが一括で読むため、この上限を設けています。

ZIP32の圧縮サイズ・参照オフセットが上限に達する場合は、そのフィールドだけZIP64に昇格します。
必要に応じてローカルヘッダーのサイズ表現、データディスクリプター、ZIP64終端レコード／ロケーターも更新・追加します。
追加フィールドの増加とデータディスクリプターの拡張を後続オフセットに反映し、他の追加フィールド・コメントはそのまま保持します。
既存のZIP64フィールドは値が小さくなってもZIP32へ縮退させません。
ZIPヘッダーの追加フィールド領域そのものが65,535バイトを超える場合は、既存フィールドを削除せずエラー終了します。

再署名・インストールは行わず、バイナリ変更後のコード署名も再利用できません。復号範囲はPython版と同じです。ページ暗号は認証付き暗号ではないため、暗号化前の原本との一致を証明するAPIではありません。

## テスト

以降のコマンドは同梱パッケージのディレクトリで実行してください。リポジトリのルートからは `swift test --package-path Vendor/FairDecKit` で実行できます。

```sh
swift test
```

合成credentialだけを使い、Python/Cから得た既知の変換値、thin／FAT32／FAT64、SINF／SUPFの対応形式、IPA内のレコード選択、破損データ・上書き防止・失敗時の後片付けを確認します。ZIP32／ZIP64の追加フィールド・コメント・日時・権限、未変更エントリの圧縮バイト列の保持と、圧縮サイズの増減によるオフセット更新も検証します。実際のcredentialやIPAはテストリソースに含めません。

実ファイルのオフセットが4GiBをまたぐ検証は、次の指定で実行します。入力の大きなゼロ領域はスパースファイルで作成し、ZIP32からZIP64への昇格後にZIPFoundationとシステムの `unzip -t` で内容を検証します。

```sh
FAIRDECKIT_LARGE_ZIP_TEST=1 swift test --filter ZIP64PromotionTests
```

4GiB超の暗号化バイナリを生成してインストール済みCLIの両モードを検証する場合は、次を実行します。
出力ディレクトリは存在しないパスを指定してください。生成IPAと2個の復号IPAで約12GiBを保存し、処理中の一時ファイルにも空き容量が必要です。
`fast` は大きなメモリを使用するため、通常のテストではこのケースをスキップします。

```sh
FAIRDECKIT_LARGE_ENCRYPTED_DIR="$PWD/runs/large-encrypted-new" \
FAIRDECKIT_IPADECRYPT_BIN="$HOME/.local/bin/ipadecrypt" \
swift test -c release --filter LargeEncryptedIPATests/testOver4GiBEncryptedBinaryWithInstalledCLI
```

バイナリ全体は4,294,975,488バイト、AES-CBCで暗号化した領域は4,294,963,200バイト（1,048,575ページ）です。
Mach-Oの `cryptsize` は32ビットなので、暗号化領域は最大の4KiB整列値とし、バイナリ全体を4GiB超にしています。
全バイトのSHA-256、ZIP CRC、`cryptid`、暗号化範囲外の末尾、ZIP64メタデータ、未変更リソースを確認し、`report.json` と各モードの時間・メモリ使用量のログを保存します。
同じ生成処理を2ページで検証する小さいテストは、通常のテストにも含めています。

実IPAとPython版の出力を照合するテストは、次の4つの環境変数を指定した場合だけ実行します。

```sh
FAIRDECKIT_IPA=/path/to/input.ipa \
FAIRDECKIT_CREDENTIAL=/path/to/credential.bin \
FAIRDECKIT_REFERENCE=/path/to/python-output.ipa \
FAIRDECKIT_OUTPUT=/path/to/new-swift-output.ipa \
FAIRDECKIT_MODE=fast \
swift test -c release --filter testDownloadedIPAAgainstPython
```

`FAIRDECKIT_MODE`は`lowMemory`または`fast`を指定し、省略時は`lowMemory`になります。`FAIRDECKIT_OUTPUT`は存在しないパスにしてください。ZIP内の全エントリについて、展開後のSHA-256・CRC32・サイズ・権限をPython版の出力と照合します。

## 同梱版について

[yyyywaiwai/FairDecKit](https://github.com/yyyywaiwai/FairDecKit) のコミット `e9d95f8d028f332dfc99f07e988bf7bb22b45211` を基に、ZIPメタデータ保持、ZIP64自動昇格、4GiB超の暗号化バイナリのテストを追加した版です。
実IPA・実credential・生成した大容量テストデータは含めません。
