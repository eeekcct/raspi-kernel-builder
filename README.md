# Raspberry Pi kernel builder (experimental)

Docker内だけにツールを入れ、ARM64 Raspberry Pi用カーネルを作るためのキットです。
ホストへのカーネル導入、bootパーティションの変更、再起動、Kubernetesの変更は行いません。

## 検証状況

- Bash構文検査とPython標準ライブラリの9テスト: 実行済み・成功。
- Dockerイメージビルド: 実行を試みたが、作成環境にDocker daemon接続がなく失敗。
- コンテナ内configure / カーネルのフルビルド / 実機起動 / Cilium / Envoy: 未検証。
- したがって、このキットは未検証部分を含みます。配布カーネルが完成済みという意味ではありません。

## 前提・初期設定

- Dockerが動作するLinux環境、またはLinux containersモードのDocker Desktop。
- ホストはamd64/arm64を想定。コンテナ内で `aarch64-linux-gnu-` ツールチェーンを使用。
- 初期ソースは **実験用の6.12系**。現行クラスタへのダウングレードを推奨するものではない。
- `kernel.commit` は、作成時に公式 `rpi-6.12.y` で確認したコミットを固定。
- `bcm2711_defconfig` (64bit/4KiBページ) が既定。
- `bcm2712_defconfig` (Pi 5系/16KiBページ) は明示指定時のみ。
- BTF、48bit仮想アドレス、独自LOCALVERSIONを設定。
- 48bit設定でユーザーのEnvoyが直ることは、まだ検証していない。
- 初期JOBS=2。所要時間や必要な空き容量は環境と設定に依存する。まずconfigureだけを試す。

**対象ノードの機種・OS・現在のカーネル・ページサイズと復旧方法を確認するまで、成果物を導入しないこと。**

## Windows PowerShellからの使い方

リポジトリを取得してDockerfileがあるフォルダーに移動する。Publicのため、cloneにGitHub認証は不要。
Gitがインストール済みなら、以下を実行する。Gitを入れたくなければ、GitHubの「Code → Download ZIP」で取得して展開してもよい。

```powershell
git clone https://github.com/eeekcct/raspi-kernel-builder.git
cd raspi-kernel-builder
```

### 1. 道具が入ったDockerイメージを作る

```powershell
docker build -t raspi-kernel-builder .
if ($LASTEXITCODE -ne 0) { throw 'Dockerイメージの作成に失敗しました' }
New-Item -ItemType Directory -Force .\out | Out-Null
$out = (Resolve-Path .\out).Path
```

### 2. まず設定を作って検査する (コンパイルはしない)

```powershell
docker run --rm --mount "type=volume,source=raspi-kernel-cache,target=/work" --mount "type=bind,source=$out,target=/out" raspi-kernel-builder configure
if ($LASTEXITCODE -ne 0) { throw '設定検証に失敗しました。ビルドへ進まないでください' }
```

成功時は `out` の下に `kernel.config` と `build-info.txt` ができる。
`CONFIG_OK` は設定検証の成功であり、カーネル起動成功ではない。

### 3. カーネルをビルドしてパッケージにする

```powershell
docker run --rm --mount "type=volume,source=raspi-kernel-cache,target=/work" --mount "type=bind,source=$out,target=/out" raspi-kernel-builder build
if ($LASTEXITCODE -ne 0) { throw 'ビルドまたはパッケージ作成に失敗しました' }
```

上記の各コマンドは、成功を確認してから次へ進む。
作業用volumeはソースと途中のビルド結果を保持する。複数コンテナから同じvolumeへ同時実行しない。
並列数を変更する場合は `docker run` に `-e JOBS=4` などを追加する。

### Pi 5向け16KiB版を明示する場合

同じ `docker run` に `-e DEFCONFIG=bcm2712_defconfig` を追加する。
ページサイズを不用意に変更しない。機種・OS・ワークロードとの互換性は別途確認が必要。

## Linux/macOSシェルから

```bash
docker build -t raspi-kernel-builder .
mkdir -p out
docker run --rm --mount type=volume,source=raspi-kernel-cache,target=/work \
  --mount "type=bind,source=$(pwd)/out,target=/out" raspi-kernel-builder configure
# 上の成功を確認してから:
docker run --rm --mount type=volume,source=raspi-kernel-cache,target=/work \
  --mount "type=bind,source=$(pwd)/out,target=/out" raspi-kernel-builder build
```

Linuxではコンテナがrootで出力を作成する。必要なら成功後に自分の出力フォルダーだけ所有者を調整する。
`--privileged`、Docker socketのコンテナへのマウント、bootディレクトリのマウントは不要。

## 出力

`out/<kernelrelease>-<defconfig>/`:

- `kernel.config`: olddefconfig後の設定。
- `build-info.txt`: ソースコミット、defconfig、コンパイラ/pahole/makeの情報。
- `btf-section.txt`: ビルドしたvmlinuxのBTFセクション確認結果 (build成功時)。
- `raspi-*.tar.xz`: boot用ファイル、対応するlib/modules、メタデータ。
- `raspi-*.tar.xz.sha256`: 配布用アーカイブのチェックサム。

アーカイブ内のカーネル名は `boot/kernel-btf48.img`。これは自作版の別名であり、展開だけで起動が切り替わるものではない。
ブートローダー/ファームウェア/initramfs/OS全体は含まない。SDカード全体のイメージでもDockerイメージでもない。
**稼働中の `/` や `/boot/firmware` に直接展開しない。導入と復旧手順は対象機に合わせて別途作る。**

## 再現性

ソースは40桁のコミットに固定し、ビルド時刻・ユーザー・ホスト名を固定する。
ただしベースの `ubuntu:24.04` とAPTパッケージは更新されるため、バイト単位の完全再現性は保証しない。
検証後にベースイメージdigest/ビルド済みbuilderイメージのdigestも固定する運用が望ましい。
ソース変更時は `kernel.commit` を更新してイメージを再ビルドする。環境変数 `KERNEL_COMMIT` での指定も可能だが、ブランチ名は受け付けない。

## GitHub Actionsでのビルド検証

`Kernel build` ワークフローは対象ファイルのPR / mainへのpushで起動し、main反映後は手動起動もできる。
Ubuntu上でDockerイメージを作成し、configure、ARM64カーネル本体・全モジュール・DTBのビルド、パッケージ作成、チェックサム検証まで行う。
初期対象は `bcm2711_defconfig` のみ。Pi 5向け16KiB版のビルド成功を保証するものではない。
ビルド並列数はGitHub runnerの `nproc` を使用し、ジョブの上限は180分。
ログ・最終設定・ビルド情報・BTFセクションの検査結果は7日保持のActions artifactに保存する。
**Release・タグ・Dockerイメージの公開はしない。カーネルのバイナリもartifactとして公開しない。実機への導入は行わない。**
ビルド成功は実機起動・Cilium/Envoy動作成功とは別。検証結果は実際のActions runで確認する。

## ローカルテスト

Pythonの追加パッケージは不要。

```bash
bash -n scripts/build.sh
python3 -m unittest discover -s tests -v
```

## 参照した一次資料

- Raspberry Pi公式ビルド手順:
  https://www.raspberrypi.com/documentation/computers/linux_kernel.html
- BTFの依存条件:
  https://github.com/raspberrypi/linux/blob/ab4372076bb840600e522ae776887ae2bc488fa6/lib/Kconfig.debug
- ARM64 VA設定:
  https://github.com/raspberrypi/linux/blob/ab4372076bb840600e522ae776887ae2bc488fa6/arch/arm64/Kconfig

## ライセンス

このリポジトリ独自のDockerfile・ビルドスクリプト・テスト・ドキュメントには、ルートのMIT `LICENSE` を適用する。
取得するLinuxソース、カーネル・モジュールなどの成果物、コンテナに含まれる第三者ソフトウェアをMITへ変更するものではない。それぞれ元のライセンスが適用される。
Linuxカーネル全体のライセンスは公式ソースの `COPYING` を参照すること。
このリポジトリにはLinuxソースやビルド済みカーネルをコミットしない。
バイナリを外部配布する場合は、その版に対応するソース・変更・設定・ビルド手順とライセンスの提供方法を別途整える。

このツールは既存のmanifestsリポジトリやクラスタを変更しない。インストール・復旧手順は対象機を確認して別途作成する。
