# Codex Pulse macOS 发布操作手册

这份文档从一台“从来没有做过 macOS 发布”的新电脑开始，完整说明如何准备开发环境、取得或迁移证书和私钥、签名、制作 Intel + Apple Silicon 通用版 DMG、提交 Apple 公证，以及发布到 GitHub Releases。

本文档适用于当前仓库的 Codex Pulse 菜单栏应用。

## 1. 先理解几个概念

发布 macOS 应用时，下面几个名词不是一回事：

| 名称 | 作用 |
| --- | --- |
| Team ID | Apple Developer 团队的固定标识。当前项目示例写作 `XXXXXXXXXX`。它不是证书，也不是密码。 |
| Developer ID Application 证书 | 给 `.app` 应用代码签名。直接分发到 GitHub、官网或 DMG 时使用它。 |
| Developer ID Installer 证书 | 给 `.pkg` 安装包签名。当前项目使用拖拽安装的 DMG，通常不需要它。 |
| Apple Development 证书 | 开发和调试使用，不能替代 Developer ID Application 做公开分发。 |
| 私钥 | 生成证书时留在本机钥匙串中的秘密部分。只有证书文件，没有私钥，无法完成签名。 |
| 签名 | 证明应用由某个开发者团队构建，并保证代码没有被篡改。 |
| 公证 Notarization | 把已签名的应用提交给 Apple 自动检查，获得 Gatekeeper 更信任的分发状态。 |
| App-Specific Password | Apple 账户的应用专用密码，仅用于 `notarytool` 登录 Apple 公证服务；不是 Apple 账户主密码。 |

当前项目的关键值：

- Team ID：`XXXXXXXXXX`
- 当前证书名称示例：`Developer ID Application: YOUR NAME (XXXXXXXXXX)`
- 应用 Bundle Identifier：`com.codexpulse.menu`
- 架构：`arm64` + `x86_64`，也就是 Apple Silicon + Intel 通用版
- 分发方式：直接分发 DMG，不走 Mac App Store
- 当前打包脚本：[`script/package_release.sh`](../script/package_release.sh)

Apple 官方参考：

- [创建 Developer ID 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [创建证书签名请求 CSR](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)
- [在分发前为 macOS 软件进行公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [自定义公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [创建 App 专用密码](https://support.apple.com/en-us/102654)

## 2. 发布流程总览

```text
新电脑准备 Xcode
        ↓
准备 Developer ID Application 证书 + 私钥
        ↓
准备 notarytool 的钥匙串凭证
        ↓
构建 arm64 + x86_64 Release
        ↓
给 App 签名
        ↓
制作 DMG
        ↓
给 DMG 签名
        ↓
提交 Apple 公证
        ↓
Staple 公证票据到 DMG
        ↓
验证签名、架构、公证
        ↓
上传 GitHub Release
```

签名和公证的顺序不能反过来：先签名，再提交公证；公证完成后，必须避免修改已经签名的 App 内容。

## 3. 新电脑第一次准备

### 3.1 安装 Xcode

从 Mac App Store 安装 Xcode。安装后第一次打开 Xcode，接受许可协议并等待组件安装完成。

打开“终端”，检查：

```bash
xcodebuild -version
xcode-select -p
```

如果开发者目录不是完整 Xcode，可以设置为：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license
```

然后再次检查：

```bash
xcodebuild -version
```

### 3.2 安装 Git 并克隆仓库

macOS 通常会在第一次执行 Git 命令时提示安装 Command Line Tools。按照系统提示安装即可。

在终端执行：

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/ScorpioQ/CodexData.git
cd CodexData
```

确认代码是干净的：

```bash
git status --short --branch
```

正常情况下应该看到类似：

```text
## main...origin/main
```

### 3.3 让脚本可执行

仓库中已包含构建和打包脚本。首次使用新电脑时执行：

```bash
chmod +x script/build_and_run.sh
chmod +x script/package_release.sh
```

先做一次不签名的调试构建，确认环境正常：

```bash
./script/build_and_run.sh --verify
```

这个步骤只验证 Xcode、项目代码和本机运行环境，不负责发布签名。

### 3.4 登录 Codex / ChatGPT

Codex Pulse 会从本机的 Codex `app-server` 获取额度数据。新电脑上需要先安装并登录 Codex 或对应的 ChatGPT 应用，让本机存在有效的登录状态。

这部分登录数据属于本机用户数据，不会放在 GitHub 仓库中，也不应该复制到仓库或公开给其他人。

## 4. 方案 A：从旧电脑迁移证书和私钥

这是最推荐的方案。它可以让新电脑继续使用同一个 Developer ID Application 身份，避免无意义地创建新证书。

### 4.1 在旧电脑检查证书是否带私钥

旧电脑打开：

```text
钥匙串访问
```

英文系统是：

```text
Keychain Access
```

左侧选择 `登录 / login`，上方选择 `我的证书 / My Certificates`，搜索：

```text
Developer ID Application
```

找到类似：

```text
Developer ID Application: YOUR NAME (XXXXXXXXXX)
```

展开证书左侧的小箭头。正常情况应该同时看到：

```text
Developer ID Application: YOUR NAME (XXXXXXXXXX)
    YOUR NAME 的私钥
```

如果只有证书，没有下面的私钥，导出的证书无法在新电脑上签名。此时应使用“方案 B”重新创建证书，或者先找回这把私钥。

### 4.2 导出 `.p12`

在“我的证书”中选中包含私钥的那一项，右键或从顶部菜单选择：

```text
文件 → 导出项目……
```

导出格式选择：

```text
Personal Information Exchange (.p12)
```

保存到临时安全位置。系统会要求设置一个导出密码。这个密码不是 Apple 账户密码，而是保护 `.p12` 文件的密码，应单独保存到密码管理器。

导出后得到类似文件：

```text
Developer ID Application.p12
```

重要：

- `.p12` 包含证书和私钥，安全级别相当于签名钥匙；
- 不要把 `.p12` 放进 Git 仓库；
- 不要通过公开网盘、公开聊天或 GitHub Issue 传输；
- 传到新电脑后，确认导入成功，再删除临时副本。

### 4.3 在新电脑导入 `.p12`

把 `.p12` 通过安全方式传到新电脑后：

1. 双击 `.p12` 文件；
2. 选择“登录 / login”钥匙串；
3. 输入导出 `.p12` 时设置的密码；
4. 如 macOS 询问是否允许访问钥匙串，选择允许或始终允许；
5. 打开“钥匙串访问”，检查“我的证书”中同时存在证书和私钥。

也可以在终端导入：

```bash
security import "/安全临时目录/Developer ID Application.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P '这里替换为导出密码' \
  -T /usr/bin/codesign
```

不要把真实密码写进脚本、Shell 历史或 Git 文件中。更安全的方式是使用钥匙串访问图形界面导入。

### 4.4 验证证书和私钥

执行：

```bash
security find-identity -v -p codesigning
```

应能看到类似：

```text
Developer ID Application: YOUR NAME (XXXXXXXXXX)
```

还可以检查证书详情：

```bash
security find-certificate -a -c "Developer ID Application" \
  "$HOME/Library/Keychains/login.keychain-db"
```

注意：`security find-identity` 显示有效身份是最重要的结果。仅仅在“钥匙串访问”中看到证书，但 `find-identity` 没有列出它，通常说明私钥缺失、证书不完整或钥匙串访问权限有问题。

## 5. 方案 B：没有旧私钥时重新创建证书

如果旧电脑损坏、私钥丢失，或者你决定建立全新的签名身份，就在新电脑创建 CSR 并申请新的 Developer ID Application 证书。

### 5.1 创建 CSR 文件

打开：

```text
钥匙串访问 → 证书助理 → 从证书颁发机构请求证书……
```

英文路径：

```text
Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority…
```

填写：

| 字段 | 填写内容 |
| --- | --- |
| 用户电子邮件地址 | 你的 Apple Developer 账户邮箱 |
| 常用名称 | 例如 `YOUR NAME Developer ID`，也可以使用你的姓名 |
| CA 电子邮件地址 | 留空 |
| 请求是 | 选择“存储到磁盘” |

保存后会得到：

```text
CertificateSigningRequest.certSigningRequest
```

CSR 文件本身通常不是秘密，但它与新电脑钥匙串中生成的私钥配对。不要删除这台电脑钥匙串中的对应私钥，否则下载的证书可能无法签名。

### 5.2 在 Apple Developer 网站申请 Developer ID Application

登录 [Apple Developer Account](https://developer.apple.com/account/)：

1. 进入“Certificates, Identifiers & Profiles”；
2. 选择左侧“Certificates”；
3. 点击右上角 `+`；
4. 在证书类型中选择 `Developer ID Application`；
5. 点击 Continue；
6. 上传刚刚生成的 `.certSigningRequest`；
7. 完成创建并下载 `.cer` 文件；
8. 双击 `.cer`，将它安装到登录钥匙串。

这里要选的是：

```text
Developer ID Application
```

不要误选：

- `Apple Development`：用于开发调试；
- `Mac App Distribution`：用于 Mac App Store；
- `Developer ID Installer`：用于 `.pkg` 安装包，不是当前 DMG 的 App 签名证书。

### 5.3 关于 `G2 Sub-CA` 和 `Previous Sub-CA`

如果 Apple Developer 页面在创建证书时显示 `Profile Type`、`G2 Sub-CA` 或 `Previous Sub-CA`：

- 新项目、新证书通常选择 `G2 Sub-CA`；
- `Previous Sub-CA` 主要用于 Apple 明确要求的旧证书兼容场景；
- 如果页面已经根据当前证书类型隐藏或固定了选项，按页面默认值继续即可；
- 不要为了“看起来兼容”而主动选旧的 Previous Sub-CA。

### 5.4 验证新证书

安装完成后执行：

```bash
security find-identity -v -p codesigning
```

确认列表中有：

```text
Developer ID Application: 你的姓名或团队名称 (XXXXXXXXXX)
```

如果能看到证书但不是有效身份，回到“钥匙串访问”展开它，确认对应私钥就在证书下面。

## 6. 准备 Apple 公证登录凭证

签名不需要 Apple 账户密码，但公证需要让 `notarytool` 登录 Apple 的公证服务。

推荐使用：

- Apple Developer 账户邮箱；
- Team ID：`XXXXXXXXXX`；
- Apple App-Specific Password。

### 6.1 创建 App 专用密码

打开 [account.apple.com](https://account.apple.com/) 并登录 Apple 账户。

进入：

```text
登录和安全 → App 专用密码 → 生成 App 专用密码
```

英文路径：

```text
Sign-In and Security → App-Specific Passwords → Generate an app-specific password
```

如果找不到这个入口，通常需要：

- Apple 账户已经打开双重认证；
- 当前账户允许使用 App 专用密码；
- 你登录的是实际拥有 Developer ID 权限的 Apple 账户。

生成后 Apple 会显示一串一次性的 App 专用密码。立即复制到密码管理器。它不是 Apple 账户主密码，也不要提交到 Git。

### 6.2 将凭证保存到钥匙串

在仓库目录执行：

```bash
xcrun notarytool store-credentials codex-notary \
  --apple-id "你的 Apple Developer 账户邮箱" \
  --team-id "XXXXXXXXXX"
```

命令会提示输入 App 专用密码。输入时终端不会显示字符，这是正常现象。

这里的 `codex-notary` 是本机钥匙串中的 profile 名称，可以自定义。本文后续统一使用这个名称。

保存后可以检查 profile 是否可用：

```bash
xcrun notarytool history --keychain-profile codex-notary
```

如果没有报“找不到 profile”，说明凭证已经保存在本机钥匙串中。profile 名称可以写入脚本参数，但 App 专用密码本身不会出现在仓库里。

## 7. 当前项目的 Release 打包脚本

当前仓库已经提供：

```text
script/package_release.sh
```

脚本会依次完成：

1. 编译 `arm64` Release；
2. 编译 `x86_64` Release；
3. 产生通用版 `.app`；
4. 如果提供签名身份，给 App 做 Developer ID 签名；
5. 创建带 `/Applications` 快捷方式的 DMG；
6. 如果提供签名身份，给 DMG 做签名；
7. 如果提供 notary profile，提交 Apple 公证；
8. 公证成功后将票据 staple 到 DMG；
9. 验证 stapler 结果。

脚本支持两个环境变量：

| 环境变量 | 是否秘密 | 作用 |
| --- | --- | --- |
| `SIGNING_IDENTITY` | 否 | Developer ID Application 的完整证书名称 |
| `NOTARY_PROFILE` | 否 | `notarytool store-credentials` 保存的 profile 名称 |

这两个变量只是告诉脚本使用哪个本机签名身份和哪条本机钥匙串凭证，不包含私钥和密码。

## 8. 制作已签名、已公证的 Universal DMG

### 8.1 找到完整签名身份

先执行：

```bash
security find-identity -v -p codesigning
```

复制完整的 `Developer ID Application: ...` 名称。当前这台电脑示例是：

```text
Developer ID Application: YOUR NAME (XXXXXXXXXX)
```

不要只写 `XXXXXXXXXX`，也不要写 `Apple Development`。

### 8.2 执行 Release 打包

在仓库根目录执行：

```bash
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (XXXXXXXXXX)' \
NOTARY_PROFILE='codex-notary' \
./script/package_release.sh 0.1.0
```

其中：

- `0.1.0` 是发布版本号和 DMG 文件名中的版本号；
- 如果项目在 Xcode 中的 Marketing Version 或 Build Number 发生变化，也应保持版本管理一致；
- 当前脚本参数主要用于输出文件名，不会自动替换项目中的所有版本字段。

完成后，重点看：

```text
dist/CodexData.app
dist/CodexPulse-0.1.0-universal.dmg
```

如果没有设置 `SIGNING_IDENTITY`，脚本会制作未签名包；如果没有设置 `NOTARY_PROFILE`，脚本不会提交公证。这适合本地测试，但不适合公开发布。

### 8.3 只签名、不公证的测试命令

如果暂时只想验证签名：

```bash
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (XXXXXXXXXX)' \
./script/package_release.sh 0.1.0
```

这种产物可以用于本机检查，但公开给其他用户前仍应完成公证。

### 8.4 只制作未签名包

```bash
./script/package_release.sh 0.1.0
```

未签名包容易在其他人的 Mac 上触发“无法验证开发者”或“应用已损坏”等提示，不要将它作为正式 Release 上传。

## 9. 发布前逐项验证

### 9.1 验证 Universal 架构

```bash
lipo -info dist/CodexData.app/Contents/MacOS/CodexData
```

应看到类似：

```text
Architectures in the fat file: ... are: x86_64 arm64
```

如果只显示一种架构，说明这不是 Universal 版本。

### 9.2 验证 App 签名

```bash
codesign --verify --deep --strict --verbose=2 dist/CodexData.app
```

成功时通常会看到：

```text
dist/CodexData.app: valid on disk
dist/CodexData.app: satisfies its Designated Requirement
```

### 9.3 查看签名身份和 Hardened Runtime

```bash
codesign -dvvv dist/CodexData.app 2>&1 | \
  grep -E 'Identifier|TeamIdentifier|Authority|Timestamp|Runtime'
```

重点确认：

- `Identifier=com.codexpulse.menu`；
- `TeamIdentifier=XXXXXXXXXX`；
- `Authority` 中有 `Developer ID Application`；
- 有 `Timestamp`；
- 有 `Runtime`，表示启用了 Hardened Runtime。

### 9.4 用 Gatekeeper 检查 App

```bash
spctl --assess --type execute --verbose=4 dist/CodexData.app
```

如果 App 已经完成签名和公证，通常会显示 accepted，且来源包含 Developer ID。

### 9.5 验证 DMG 的公证票据

```bash
xcrun stapler validate dist/CodexPulse-0.1.0-universal.dmg
```

成功时会显示：

```text
The validate action worked!
```

也可以检查 DMG 签名：

```bash
codesign --verify --verbose=2 dist/CodexPulse-0.1.0-universal.dmg
```

### 9.6 查看公证历史和日志

```bash
xcrun notarytool history --keychain-profile codex-notary
```

如果最近一次失败，需要拿到 submission ID 后查看详细日志：

```bash
xcrun notarytool log SUBMISSION_ID \
  --keychain-profile codex-notary
```

Apple 的公证检查可能包含签名链、Hardened Runtime、嵌套代码、恶意软件扫描和包内容一致性等项目。不要只看到上传成功就认为公证成功，必须确认状态是 `Accepted`。

## 10. 在干净环境测试

正式上传 GitHub 前，建议在另一台 Mac 或一个没有旧版本缓存的用户账户中测试：

1. 下载最终 DMG；
2. 双击打开 DMG；
3. 将应用拖到 `Applications`；
4. 从“应用程序”目录启动；
5. 确认菜单栏显示额度；
6. 确认应用不显示在程序坞；
7. 确认菜单中的百分比、倒计时、状态和开机启动选项正常；
8. 确认 Intel Mac 和 Apple Silicon Mac 都可以启动；
9. 确认系统语言为中文和英文时界面都正确。

首次启动时，如果 macOS 弹出权限、登录或网络相关提示，应记录具体文字。不要直接通过关闭 Gatekeeper 或删除扩展属性来掩盖发布问题。

## 11. 发布到 GitHub Releases

### 11.1 发布前检查仓库中没有秘密

在提交前执行：

```bash
git status --short --ignored
```

以下文件绝对不要提交：

```text
*.p12
*.pfx
*.key
*.pem
*.p8
*.cer
*.certSigningRequest
*.mobileprovision
```

其中 `.cer` 通常只包含公钥证书，泄露风险低于 `.p12`，但也没有必要放进公开仓库。真正必须保护的是私钥和登录凭证。

还不能提交：

- App-Specific Password；
- Apple 账户主密码；
- `notarytool` 密码；
- 任何钥匙串导出文件；
- Codex、ChatGPT 或其他服务的登录 token；
- `xcuserdata`、`.derivedData`、`.releaseDerivedData` 等本机生成文件。

当前项目的 `dist`、构建缓存和 Xcode 用户数据已经通过忽略规则排除。它们可以留在本机，但不需要为了换电脑而提交。

### 11.2 检查差异并提交代码

```bash
git add .
git diff --cached --check
git diff --cached --stat
```

确认没有证书、密码、个人路径或本机缓存后提交：

```bash
git commit -m "Release 0.1.0"
git push origin main
```

### 11.3 创建版本标签

```bash
git tag -a v0.1.0 -m "Codex Pulse 0.1.0"
git push origin v0.1.0
```

建议 Tag 和 DMG 版本号一致，例如：

```text
Tag: v0.1.0
DMG: CodexPulse-0.1.0-universal.dmg
```

### 11.4 创建 GitHub Release

在 GitHub 仓库页面：

1. 点击右侧 `Releases`；
2. 点击 `Draft a new release`；
3. 选择刚刚推送的 Tag，例如 `v0.1.0`；
4. 填写 Release 标题，例如 `Codex Pulse 0.1.0`；
5. 把已公证的 DMG 拖到附件区域；
6. 写清楚支持 `Apple Silicon + Intel`；
7. 点击发布。

上传前可以生成 SHA-256：

```bash
shasum -a 256 dist/CodexPulse-0.1.0-universal.dmg
```

把结果放到 Release Notes，方便用户验证下载文件是否完整。

## 12. 一条命令式的日常发布流程

新电脑完成证书导入和 notary profile 配置后，每次发布通常只需要：

```bash
cd ~/Projects/CodexData
git pull --ff-only origin main

SIGNING_IDENTITY='Developer ID Application: YOUR NAME (XXXXXXXXXX)' \
NOTARY_PROFILE='codex-notary' \
./script/package_release.sh 0.1.0

lipo -info dist/CodexData.app/Contents/MacOS/CodexData
codesign --verify --deep --strict --verbose=2 dist/CodexData.app
xcrun stapler validate dist/CodexPulse-0.1.0-universal.dmg
shasum -a 256 dist/CodexPulse-0.1.0-universal.dmg
```

确认验证全部通过后，再创建 GitHub Tag 和 Release。

## 13. 常见问题

### 13.1 `No identity found`

先检查：

```bash
security find-identity -v -p codesigning
```

如果没有 `Developer ID Application`：

1. 检查证书是否导入到了“登录”钥匙串；
2. 展开证书，确认下面有私钥；
3. 确认不是只导入了 `.cer`；
4. 如果是从旧电脑迁移，重新导出并导入 `.p12`；
5. 如果私钥已经丢失，按方案 B 重新创建 CSR 和证书。

### 13.2 只有 `Apple Development`

这是开发证书，不能代替 Developer ID Application。到 Apple Developer 网站创建或下载 `Developer ID Application`，安装后重新运行：

```bash
security find-identity -v -p codesigning
```

### 13.3 `notarytool` 找不到 profile

重新保存一次：

```bash
xcrun notarytool store-credentials codex-notary \
  --apple-id "你的 Apple Developer 账户邮箱" \
  --team-id "XXXXXXXXXX"
```

然后检查：

```bash
xcrun notarytool history --keychain-profile codex-notary
```

### 13.4 公证失败

先保存 submission ID，然后执行：

```bash
xcrun notarytool log SUBMISSION_ID \
  --keychain-profile codex-notary
```

常见原因：

- 使用了 Apple Development 而不是 Developer ID Application；
- App 没有 Hardened Runtime；
- App 内部某个嵌套可执行文件没有签名；
- 签名后又修改了 App 内容；
- DMG 内放入了不同于已签名版本的 App；
- 使用了错误的 Team ID；
- 构建产物中包含不应分发的调试文件或个人文件；
- 公证凭证对应的 Apple Developer 团队不是证书所属团队。

修复后必须重新构建、重新签名、重新提交，不能继续使用已经失败或被修改过的旧包。

### 13.5 用户看到“应用已损坏”

不要先让用户执行：

```bash
xattr -cr /Applications/CodexData.app
```

这会绕过一部分检查，不能解决正式发布问题。先在发布机器验证：

```bash
codesign --verify --deep --strict --verbose=2 dist/CodexData.app
spctl --assess --type execute --verbose=4 dist/CodexData.app
xcrun stapler validate dist/CodexPulse-0.1.0-universal.dmg
```

然后从 GitHub 重新下载 DMG，确认下载没有被截断或替换。

### 13.6 证书过期或私钥泄露

如果只是证书过期，通常需要创建新证书并用新证书重新发布。

如果 `.p12`、私钥或 App-Specific Password 泄露：

1. 立即在 Apple 账户中撤销 App-Specific Password；
2. 在 Apple Developer 账户中撤销受影响的 Developer ID 证书；
3. 在新电脑重新生成 CSR 和私钥；
4. 创建新的 Developer ID Application 证书；
5. 重新保存 `notarytool` profile；
6. 重新构建、签名、公证和发布；
7. 检查 Git 历史和 GitHub Actions 日志，确认没有继续暴露秘密。

## 14. 新电脑需要保留什么、不需要保留什么

只要 GitHub 仓库完整，新电脑可以直接 `git clone` 继续开发。通常不需要把旧电脑上的这些内容复制过去：

- `.derivedData`；
- `.releaseDerivedData`；
- `dist`；
- `xcuserdata`；
- Xcode 的本机窗口布局和断点；
- 旧电脑的 Codex 登录缓存。

需要重新准备或迁移的是：

- Xcode；
- Developer ID Application 证书和私钥；
- `notarytool` 的钥匙串 profile；
- Codex / ChatGPT 本机登录状态；
- 如果使用 GitHub SSH，则重新配置 GitHub SSH Key；
- 如果使用 GitHub CLI，则重新执行 `gh auth login`。

证书私钥和 notarytool profile 是“机器上的发布环境”，不是项目源代码的一部分。不要把它们提交到 GitHub；换电脑时通过安全方式重新建立即可。
