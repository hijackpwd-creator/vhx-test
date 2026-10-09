# 越狱 iOS VHX 测试程序

这是独立命令行程序，无需注入 dylib。包含 Objective-C 源码和 Theos 配置；不包含预编译二进制。当前交付环境没有 Apple SDK、clang 或 iOS 真机，未进行编译或真机网络验证。

## 与原函数的对应关系

1. 将传入字符串直接追加 `/vhx`，不清理末尾斜杠。传入 `https://example.com` 会请求 `https://example.com/vhx`；传入 `https://example.com/` 会请求 `https://example.com//vhx`。请传入不含查询参数、片段和末尾斜杠的服务器地址。
2. 使用 NSMutableURLRequest，方法 GET，timeoutInterval 为传入值。
3. 使用 NSURLSession 发起异步请求，再用 dispatch_semaphore_wait 等待 `timeout + 2` 秒。
4. 等待超时后 cancel，并返回 false；正常完成则返回回调写入的结果。

已根据提供的 block_invoke 更新：无 NSError、HTTP 状态码等于指定值、响应数据非空，正文按 UTF-8 解码并使用 whitespaceAndNewlineCharacterSet 去除首尾空白，最后 caseInsensitiveCompare 与 `ok` 比较相等。

反编译输出中的 `stru_B8.segname` 未给出实际数值，不能直接认定为 200。本程序默认使用 200，允许通过第四个参数指定实际状态码。需要查看该比较指令附近的汇编或对应数据，确认常量后再设置。

注意原反编译逻辑的边界：UTF-8 解码失败时字符串为 nil，对 nil 调用 caseInsensitiveCompare 返回 0，原逻辑可能将非空且无效 UTF-8 的正文误判为成功。本程序增加 nil 检查，使该情况返回 false，这是有意采用的严格判定差异。

原 `_sharedSession` 的初始化配置同样未知，本程序采用 NSURLSession.sharedSession，保留系统默认 TLS 校验、缓存、Cookie 和重定向行为。因此结果反映最终响应，不代表每次都直接访问源站，也不保证与原程序配置完全一致。额外校验 HTTP(S) URL 和有限正超时，属于测试程序的输入保护。

## 方法一：Mac 上使用 Xcode SDK 编译

在源码目录执行（需要安装 Xcode 和 iPhoneOS SDK）：

```bash
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=12.0 \
  -fobjc-arc -fblocks -Wall -Wextra -framework Foundation main.m -o vhx-test
```

将二进制上传至自己的越狱设备，例如 `/var/mobile/vhx-test`，在设备终端使用已有的 ldid 签名：

```bash
cd /var/mobile
ldid -S vhx-test
chmod 755 vhx-test
./vhx-test 'https://example.com' 5 1
```

普通网络请求不需要额外私有 entitlement。设备必须允许执行自行签名的命令行二进制；具体取决于越狱环境。rootless 环境若 PATH 找不到 ldid，可检查是否安装在 `/var/jb/usr/bin/ldid`。网络错误不会通过忽略证书的方式规避。

## 方法二：Theos 编译安装

需要已配置 THEOS、iOS SDK、编译工具链和签名工具。在源码目录执行：

```bash
# rootful
make clean
make package

# rootless（与上面的 rootful 二选一）
make clean
make package THEOS_PACKAGE_SCHEME=rootless
```

将生成的 `packages/*.deb` 传到自己的设备，使用设备上的包管理工具安装，或者：

```bash
sudo dpkg -i /path/to/package.deb
vhx-test 'https://example.com' 5 1
```

安装通常需要设备上的 root 权限。如果没有 sudo，请切换到已有 root shell 后运行 dpkg。rootful 安装路径为 `/usr/bin/vhx-test`，rootless 使用 Theos 路径映射后通常为 `/var/jb/usr/bin/vhx-test`。也可直接采用方法一，将独立二进制放到 `/var/mobile` 执行。

## 使用与判定

```bash
# 超时 5 秒，详细输出
./vhx-test 'https://your-server.example' 5 1

# 超时 10 秒，仅输出结果
./vhx-test 'https://your-server.example' 10 0

# 第四个参数指定应匹配的 HTTP 状态码（默认 200）
./vhx-test 'https://your-server.example' 5 1 200
```

输出 `RESULT=true` 或 `RESULT=false` 和耗时。详细模式还输出最终 URL、HTTP 状态、响应头、响应字节数、最多 4096 字节的原始字节正文预览以及 NSError 信息。正文预览只用于观察；成功判断使用完整正文，超过 4096 字节也不会截断后参与判断。

| 退出码 | 意义 |
| --- | --- |
| 0 | 状态码匹配且正文 trim 后不区分大小写等于 ok |
| 1 | 状态码不匹配、正文不匹配/为空/无效 UTF-8、网络错误、无效 URL 或等待超时 |
| 2 | 命令行参数格式错误 |

参数超时范围为 `(0, 86400]` 秒。请求 timeoutInterval 不等价于严格的端到端总时长限制；程序额外用信号量设置等待上限。等待超时并取消后，回调可能稍后触发，但调用结果保持 false。

如需验证异常路径，可在你控制的测试服务器上让 `/vhx` 分别返回 200、404、503，或者延迟响应，观察结果和错误信息。不建议用随机外部 IP 模拟超时，网络环境会影响实际错误类型。

## 正文判定示例（状态码匹配且无网络错误时）

| 正文 | 结果 |
| --- | --- |
| `ok` / `OK` / `Ok` | true |
| 首尾有空格或换行的 `ok` | true |
| 空正文 / 仅空白 | false |
| `okay` / JSON 字符串 `"ok"` | false |
| 无效 UTF-8 | false（原反编译代码可能误判 true） |

## 复查修正（1.0.1）

- 详细响应输出移到等待成功之后，避免日志阻塞影响信号量完成通知。回调只做结果判定、保存响应引用和 signal；等待超时的路径直接返回 false，不读取回调可能仍在写入的变量。
- 正文预览使用 fwrite 输出原始字节，避免截断 UTF-8 多字节字符导致误报，也保留嵌入 NUL 的字节。终端展示仍取决于终端编码。详细模式关闭时不输出响应正文。
- 方法内部也校验超时范围、状态码范围和 session，避免复用该方法时绕过命令行校验。
- 显式包含 stdint.h，Theos 显式启用 blocks；rootless 最低部署版本为 iOS 15，rootful 为 iOS 12。最新 Theos rootless scheme 自动处理安装前缀和包架构，无需把 control 永久改为 iphoneos-arm64。
- ARC 会保留异步回调捕获的信号量和 __block 对象；等待超时后回调仍可安全触发。正常路径在 signal 后读取结果，超时路径不读取结果。
- 不应机械照抄反编译中的 objc_retain/objc_release；本实现使用 ARC 管理对象。
- RESULT 的 elapsed 包含详细模式下输出日志的时间，属于整个方法调用耗时，而不是纯网络耗时。

本次为源码审查和修正，未在 Apple SDK 下编译，未在 iOS 真机运行。要完全还原仍需确认 `stru_B8.segname` 的实际数值及原 `_sharedSession` 配置。

可在 Mac 编译出二进制后运行随附的本地集成验证脚本（不需要真实服务器）：

```bash
python3 verify.py ./vhx-test
```

该脚本会启动本机 HTTP 服务，覆盖正文大小写/空白、空正文、错误正文、无效 UTF-8、状态码不匹配、可配置状态码、请求超时和参数错误。它验证编译后的真实程序；本交付环境无法执行此测试。

参考： https://theos.dev/docs/rootless 和 https://theos.dev/docs/packaging 。

## GitHub Actions 编译

源码包内包含 `.github/workflows/build-ios.yml`。上传到仓库时，`.github` 必须位于仓库根目录，源码位于根目录的 `vhx-test/main.m`，不要把整个包再嵌套一层目录。

工作流使用 macos-15-intel 的 Xcode SDK，先编译同一份代码的 macOS 版本并运行 11 项集成验证，再交叉编译 iOS arm64。生成最低支持 iOS 12 和 iOS 15 的两份独立二进制，使用 Homebrew ldid 自签名。它不会生成 deb 或发布 Release。

上传到 GitHub 后：Actions → Build VHX iOS → Run workflow。push 修改相关源码也会触发构建。成功后，在该次运行的 Artifacts 中下载 `vhx-test-ios-arm64`，解开其中的 tar.gz。内含 ios12-arm64/vhx-test、ios15-arm64/vhx-test、SHA256 校验值和源码提交号。tar.gz 保留执行权限。

rootful iOS 12+ 可选择 ios12-arm64，rootless iOS 15+ 可选择 ios15-arm64。复制选定的 vhx-test 到设备 /var/mobile 后执行：

```bash
cd /var/mobile
chmod 755 vhx-test
./vhx-test 'https://your-server.example' 5 1 200
```

macOS 版测试通过不等于 iOS 真机验证通过。最终仍需在目标越狱设备运行；其签名执行策略、网络权限、TLS 和缓存配置可能影响运行。

当前仅准备了工作流；尚未在 GitHub 提交或启动构建。

目标设备为 arm64e 时，本程序仍以 arm64 编译。普通 CLI 不需要使用 arm64e ABI；arm64e 设备可运行 arm64 程序。此结论针对独立命令行程序，不适用于向 arm64e 系统进程注入的 dylib。参考 Theos rootless 文档的 CLI 架构说明。
