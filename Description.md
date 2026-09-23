# TermOnePlus Tools 项目说明

## 用途

将 TermOne Plus 5.7.0（开源 Android 终端模拟器，applicationId `com.termtools.box`）改造为 Termux 风格环境，面向 Android 4.4+：

- 自定义 `$PREFIX` / `$HOME` / `$TMPDIR` 目录结构
- 启动时后台运行 Dropbear SSH（端口 8022）
- Shell 优先级 `fish > bash > zsh > /system/bin/sh`（bash 已删除）
- 内置约 70+ 静态 ARM32 工具（busybox、curl、python、jq、nano、vim、git、wget、strace、lsof、tcpdump 等）
- `pkg` 包管理器，源指向 900+ 静态二进制仓库
- 双目录运行日志 + 早期 UncaughtExceptionHandler，用于诊断 Android 4.4 崩溃

## 架构

```
本仓库（tools/resources overlay）──┐
                                  ├──> GitHub Actions ──> term-full-release.apk
上游主源码 GitLab termoneplus ────┘
```

- 本仓库包含 Java 补丁、assets 工具、构建脚本；上游源码由 CI checkout 或本地同步
- 无本地 Android SDK，编译全部在 GitHub Actions 完成
- 本地 Git 走 SSH（`git@github.com:addallno/termoneplus-tools.git`），HTTPS 443 不通

### 关键类

| 文件 | 职责 |
|------|------|
| `Application.java` | onCreate 建目录、linkNativeLibs、装工具、启动 dropbear |
| `RunLog.java` | 双目录日志（external `files/logs` 优先 + internal fallback） |
| `Term.java` | 主 Activity，bind TermService、创建会话 |
| `TermService.java` | 前台服务，持有 TerminalSession |
| `ShellTermSession.java` | 创建 shell 进程、注入环境变量 |
| `TermSettings.java` | `detectPreferredShell()` 选 shell |
| `ServiceManager.java` | bind/unbind TermService |
| `CommandCollector.java` | 收集远程命令；`pending==0` 时立即回调（修复卡死） |
| `Installer.java` | assets 安装到 $PREFIX，0 字节重装 |
| `libtermexec` | JNI：`Process.java` / `TermIO.java`，loadLibrary 带 try-catch |

### 目录结构（运行时）

```
/data/data/com.termtools.box/files/
  usr/          # $PREFIX
    bin/        # 静态工具（~70 个 ARM32 ELF）+ pkg + dropbear + fish
    etc/        # mkshrc、host keys
    lib/        # native libs 副本
    tmp/        # $TMPDIR
  home/         # $HOME（.ssh/ 等）
  logs/         # 内部日志 fallback
/sdcard/Android/data/com.termtools.box/files/logs/  # 外部日志（优先）
```

## 构建与命令

### CI（.github/workflows/build.yml）

```bash
# 触发：push master 或 workflow_dispatch
# 步骤：JDK17 → Android SDK(36/NDK 23.2) → musl 重编 dropbear → musl 编 fish
#     → 签名 → elf-cleaner → gradlew :term:assembleFullRelease → 上传 artifact
```

### 下载产物（需带认证）

```bash
TOKEN=$(gh auth token)
# artifact id 10733294219（Run 35822773265 / commit 180c760）
curl -L -f \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -o artifact.zip \
  "https://api.github.com/repos/addallno/termoneplus-tools/actions/artifacts/10733294219/zip"
unzip artifact.zip -d extracted/
# APK: extracted/term-full-release.apk（约 26 MB）
```

**注意**：绝不能对同一文件并发跑多个 curl，会导致 zip 损坏；下载后校验大小（约 25,152,697）与签名。

### 本地校验

```bash
sh -n term/src/main/assets/tools/usr/bin/pkg   # pkg 语法
unzip -l term-full-release.apk | grep META-INF  # 签名存在
```

### 设备端读日志

```bash
# 优先
/sdcard/Android/data/com.termtools.box/files/logs/run-YYYY-MM-DD.log
# 若无
/data/data/com.termtools.box/files/logs/run-YYYY-MM-DD.log   # 需 root 或 run-as
```

## 依赖

- **构建**：AGP 9.2.1、Gradle 9.7、compileSdk/targetSdk 36、minSdk 16、NDK 23.2.8568313、Java 17
- **CI 脚本**：`scripts/build-dropbear-musl.sh`、`scripts/build-fish-musl.sh`（musl 静态交叉编译）
- **pkg 远程源**：`polaco1782/linux-static-binaries` @ `armv7l-eabihf/`（926 个 ARM32 静态 ELF，GPL-3.0）
- **设备**：Android 4.4.2 (API 19) 实测崩溃诊断中；APK 含 4 ABI 的 `libterm-system.so`

## 已知问题 / 待办

1. **Android 4.4 启动即崩**（无日志 → 已加全链路 RunLog，待真机验证）  
   候选根因：ServiceManager bind IllegalStateException、native loadLibrary、installTools、CommandCollector 卡住
2. PLAN.md 中 Task 1–8 部分 checkbox 未逐项勾选（代码已大体实现）
3. CI 临时签名 keystore 可固化到 secrets（`KEYSTORE_B64` / `KEYSTORE_PASS`）
4. Description.md 此前缺失，本次补齐

## 提交历史（近期）

| Commit | 说明 |
|--------|------|
| `180c760` | fix: ShellTermSession super() 必须为首语句 |
| `b29595e` | fix: 双目录 RunLog + 早期 handler + 全链路插桩 |
| （本次） | feat: 内置 busybox + 30+ 实用静态工具（polaco + therealsaumil） |
| `67426fd` | fix: v1 签名 + try-catch + 文件日志 |
| `7bd6155` | feat: pkg 包管理器 |
| `141293f` 等 | fish ARM32 musl 静态交叉编译系列 |
