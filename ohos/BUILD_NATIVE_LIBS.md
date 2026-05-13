# mpv_audio_kit OHOS 原生库编译文档

## 一、编译产物概览

| 文件                 | 说明                                                                   |
| -------------------- | ---------------------------------------------------------------------- |
| `libmpv.so` (~16 MB) | mpv 0.41.0 播放器，静态链入 FFmpeg 7.1.1 + libplacebo 7.349.0 + libc++ |

**目标架构：** `aarch64-linux-ohos` (arm64-v8a)

**编译策略：**

- FFmpeg 编译为 **静态库**，仅启用音频相关的 decoder/parser/filter/protocol/bsf，与其他平台（Android/iOS/macOS）保持一致
- libplacebo 编译为 **静态库**，禁用所有 GPU 后端
- mpv 编译为 **动态库** (libmpv.so)，`-Dauto_features=disabled` 仅启用必要功能
- C++ 标准库 (libc++) **静态链入**，避免 OHOS 设备运行时 libc++\_shared.so 版本不匹配
- 最终只输出一个 `libmpv.so`，无外部依赖（除系统 libc/libm/libdl）

---

## 二、环境搭建（macOS）

### 2.1 安装 DevEco Studio

从华为官网下载安装 DevEco Studio，确保 OHOS SDK 在默认路径：

```
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/
```

验证 NDK 工具链：

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin/clang --version
# 应显示：OHOS (dev) clang version 15.0.4
```

### 2.2 安装构建工具

```bash
brew install meson ninja pkg-config nasm
```

验证版本：

```bash
meson --version    # >= 0.62.0
ninja --version    # >= 1.10
pkg-config --version
```

### 2.3 安装 Python 依赖

libplacebo 的 GLSL 预处理器需要 `jinja2`，需为 **meson 使用的 Python** 安装：

```bash
# 查看 meson 使用哪个 Python
head -1 $(which meson)
# 例如输出: #!/opt/homebrew/opt/python@3.14/bin/python3.14

# 为对应 Python 安装 jinja2
# 如果 pip 正常：
python3.14 -m pip install jinja2

# 如果 pip 有问题（如 expat 错误），从系统 Python 复制纯 Python 包：
mkdir -p ~/Library/Python/3.14/lib/python/site-packages
cp -r ~/Library/Python/3.9/lib/python/site-packages/jinja2 ~/Library/Python/3.14/lib/python/site-packages/
cp -r ~/Library/Python/3.9/lib/python/site-packages/markupsafe ~/Library/Python/3.14/lib/python/site-packages/
```

---

## 三、编译流程

### 3.1 一键编译

```bash
cd /path/to/mpv_audio_kit
chmod +x ohos/build_ohos_libmpv.sh
./ohos/build_ohos_libmpv.sh
```

脚本会自动执行以下 5 个步骤。

### 3.2 详细步骤说明

#### Step 1：编译 FFmpeg 7.1.1（静态库，纯音频）

- 从 https://ffmpeg.org 下载源码
- 使用 OHOS NDK clang 交叉编译
- 编译为 **静态库** (`--enable-static --disable-shared`)，最终链入 libmpv.so
- 与其他平台保持一致的编解码器/协议/滤镜配置：
  - **Decoder**: aac/flac/mp3/opus/vorbis/wavpack/alac/ape/dca/pcm\_\* 等 70+ 音频解码器
  - **Protocol**: file/http/https/tcp/udp/tls/data/pipe/async/cache/crypto/subfile
  - **Parser**: aac/ac3/flac/mpegaudio/opus/vorbis/dca/cook
  - **BSF**: aac_adtstoasc/extract_extradata/null/setts
  - **Filter**: aformat/amix/aresample/atempo/volume/equalizer/loudnorm/afade 等 26 个音频滤镜
- 启用 `--enable-lto=thin` 链接时优化
- 禁用所有视频/硬件加速/GUI 相关功能
- 输出：`.a` 静态库 + 头文件 + pkgconfig

#### Step 2：编译 libplacebo 7.349.0（静态库，无 GPU）

- 从 GitHub 下载源码 + fast_float 子模块（GitHub tarball 不含 git submodule）
- Meson 交叉编译，`--default-library=static`
- 禁用所有 GPU 后端：vulkan/opengl/d3d11/shaderc/glslang
- 输出：`libplacebo.a` + 头文件 + pkgconfig
- **注意**：libplacebo 的 `convert.cc` 使用 C++ `<charconv>` 的 `std::to_chars(float)`，需在最终链接时静态链入 libc++（见 Step 4）

#### Step 3：为 mpv 创建 libass 桩文件（关键步骤）

mpv 0.41.0 对 libass 有硬依赖，但我们做纯音频构建不需要字幕渲染。解决方案：

1. **创建桩头文件** `ass/ass.h` — 仅含类型声明 + `ass_library_version()` 内联函数
2. **创建桩 pkgconfig** `libass.pc` — 让 meson 能找到 "libass"
3. **从 `meson.build` 移除 3 个 libass 源文件**：`sub/ass_mp.c`、`sub/osd_libass.c`、`sub/sd_ass.c`
4. **创建 `sub/osd_libass_stub.c` 桩实现** — 提供被其他编译单元引用的所有导出函数的空实现

桩文件提供的函数（共 12 个）：

| 来源文件       | 桩函数                            | 引用方                               |
| -------------- | --------------------------------- | ------------------------------------ |
| `osd_libass.c` | `osd_destroy_backend()`           | sub/osd.c                            |
|                | `osd_get_function_sym()`          | sub/osd.h                            |
|                | `osd_mangle_ass()`                | sub/osd.h                            |
|                | `osd_get_text_size()`             | sub/osd.h                            |
|                | `osd_set_external()`              | sub/osd.h                            |
|                | `osd_set_external_remove_owner()` | player/client.c                      |
|                | `osd_object_get_bitmaps()`        | sub/osd.c                            |
| `sd_ass.c`     | `sd_ass_fmt_offset()`             | sub/filter_sdh.c, sub/filter_regex.c |
|                | `sd_ass_pkt_text()`               | sub/filter_sdh.c, sub/filter_regex.c |
|                | `sd_ass_to_plaintext()`           | sub/filter_sdh.c, sub/filter_regex.c |
|                | `sd_ass` (struct)                 | sub/dec_sub.c                        |
|                | `mp_sub_filter_opts` (struct)     | options/options.c                    |

> `ass_mp.c` 的导出函数仅在被移除的 3 个文件内部互相引用，无需提供桩实现。

#### Step 3b：为 OHOS 适配 OpenSL ES 音频输出驱动

mpv 的 `ao_opensles.c` 基于 Android 的 OpenSL ES 扩展，OHOS 的 OpenSL ES 实现有关键差异。解决方案：

1. **替换 `ao_opensles.c`** — 使用 OHOS 专有的 `SLOHBufferQueueItf` API 替代标准/Android 的 `SLBufferQueueItf`
2. **使用 `SL_IID_OH_BUFFERQUEUE`** — OHOS 不支持标准的 `SL_IID_BUFFERQUEUE`，必须使用 OH 扩展接口
3. **使用 `GetBuffer` + `Enqueue` 模式** — OHOS 回调中需先调用 `GetBuffer()` 获取可写 buffer，填充数据后再 `Enqueue()`
4. **PCM 格式固定 S16** — OHOS OpenSL ES 仅支持 `SL_PCMSAMPLEFORMAT_FIXED_16`
5. **回调签名差异** — OHOS 回调多一个 `SLuint32 size` 参数

OHOS NDK 提供的 OpenSL ES：

- 头文件：`OpenSLES.h` + `OpenSLES_OpenHarmony.h`（OH 扩展）
- 库：`$SYSROOT/usr/lib/aarch64-linux-ohos/libOpenSLES.so`
- 支持的 SLInterfaceID：`SL_IID_ENGINE`、`SL_IID_PLAY`、`SL_IID_VOLUME`、`SL_IID_OH_BUFFERQUEUE`

#### Step 4：编译 mpv 0.41.0（libmpv，纯音频）

- 从 GitHub 下载源码
- Meson 交叉编译，`--default-library=shared`
- 使用与其他平台一致的 meson 配置：
  ```
  -Dauto_features=disabled -Dgpl=true -Dlibmpv=true -Dcplayer=false
  -Dbuild-date=false -Dtests=false -Dgl=disabled -Dplain-gl=disabled
  -Dopensles=enabled -Dzlib=enabled -Db_lto=true
  ```
- **静态链入 C++ 标准库**：交叉编译文件中 link_args 添加 `-lc++_static -lc++abi`，解决 libplacebo 的 `std::to_chars(float)` 在 OHOS 设备运行时找不到的问题
- FFmpeg + libplacebo 以静态库链入 libmpv.so
- 输出：`libmpv.so`（约 16MB，包含所有依赖）

#### Step 5：收集产物到 `ohos/libs/arm64-v8a/`

- 仅复制 `libmpv.so`（FFmpeg 和 libplacebo 已静态链入，无单独 .so）

### 3.3 自定义 SDK 路径

如果 DevEco Studio 不在默认路径：

```bash
OHOS_SDK=/path/to/sdk ./ohos/build_ohos_libmpv.sh
```

---

## 四、自动编译集成

在 `ohos/hvigorfile.ts` 中已添加前置检测逻辑：

```typescript
const requiredLib = resolve(libDir, "libmpv.so");
if (!existsSync(requiredLib)) {
  execSync(`bash "${script}"`, { stdio: "inherit" });
}
```

**效果：** 其他开发者 clone 仓库后，首次运行 `flutter build hap` 或在 DevEco Studio 中编译时，如果 `ohos/libs/arm64-v8a/libmpv.so` 不存在，会自动触发 `ohos/build_ohos_libmpv.sh`，无需手动操作。

**前提条件：** 目标机器必须是 macOS + 已安装上述构建依赖（meson/ninja/pkg-config/jinja2）。

---

## 五、产物验证

```bash
TOOLCHAIN=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm

# 检查架构
file ohos/libs/arm64-v8a/libmpv.so
# 应显示：ELF 64-bit LSB shared object, ARM aarch64

# 检查动态依赖（应仅有系统库）
$TOOLCHAIN/bin/llvm-readelf -d ohos/libs/arm64-v8a/libmpv.so | grep NEEDED
# 应仅有：libc.so, libOpenSLES.so (无 libavcodec/libass/libplacebo/libc++_shared 等)

# 检查无 mpv 内部未定义符号
$TOOLCHAIN/bin/llvm-nm ohos/libs/arm64-v8a/libmpv.so | grep ' U ' | grep -E 'mp_|mpv_|osd_|sd_ass|ass_mp'
# 应无输出

# 检查 C++ 符号已静态解析
$TOOLCHAIN/bin/llvm-nm -D ohos/libs/arm64-v8a/libmpv.so | grep to_chars
# 应显示 T（已定义）而非 U（未定义）
```

---

## 六、清理与重建

```bash
# 完全清理（删除所有中间产物 + 源码）
rm -rf ohos/build/ ohos/libs/arm64-v8a/

# 仅清理编译产物（保留下载的源码）
rm -rf ohos/build/install \
       ohos/build/ffmpeg-*/config.mak \
       ohos/build/libplacebo-*/build-ohos \
       ohos/build/mpv-*/build-ohos \
       ohos/libs/arm64-v8a/

# 重新编译
./ohos/build_ohos_libmpv.sh
```

---

## 七、已知问题与解决方案

| 问题                                              | 原因                                                                                              | 解决方案                                   |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `jinja2 not found`                                | meson 的 Python 版本没装 jinja2                                                                   | 见 2.3 节安装方法                          |
| `fast_float.h not found`                          | GitHub tarball 不含 git submodule                                                                 | 脚本已自动下载 fast_float v6.1.1           |
| `ass/ass.h not found`                             | mpv 对 libass 有未保护的 `#include`                                                               | 脚本创建桩头文件 + 桩 pkgconfig            |
| `libplacebo not found`                            | mpv 0.41.0 硬依赖 libplacebo                                                                      | 脚本编译 libplacebo 静态库并链入           |
| `_ZNSt4__n18to_charsEPcS0_f: symbol not found`    | libplacebo 的 `convert.cc` 使用 `std::to_chars(float)`，OHOS 设备的 `libc++_shared.so` 不含此符号 | mpv 链接时静态链入 `-lc++_static -lc++abi` |
| `osd_set_external_remove_owner: symbol not found` | 移除 `osd_libass.c` 后其导出函数丢失，但 `player/client.c` 等仍引用                               | `osd_libass_stub.c` 提供 7 个空实现        |
| `mp_sub_filter_opts: symbol not found`            | `sd_ass.c` 中定义的 option struct 被 `options.c` 引用                                             | 桩文件提供空的 `mp_sub_filter_opts` 定义   |
| `sd_ass: symbol not found`                        | `sd_ass.c` 中定义的 driver struct 被 `dec_sub.c` 引用                                             | 桩文件提供仅含 `.name` 的空 `sd_ass` 定义  |

### 7.1 音频输出初始化失败 (audio output initialization failed)

**现象：** `libmpv.so` 编译成功，但播放音频时报错 `audio output initialization failed`。

**排查过程：**

1. 检查 meson 构建日志发现：
   ```
   Library OpenSLES skipped: feature opensles disabled
   ```
2. 根因：meson 配置使用了 `-Dauto_features=disabled` 禁用所有可选功能，但未显式启用任何音频输出驱动，导致 `libmpv.so` 中**没有任何音频输出驱动**（连 `null` 以外的都没有）。

**解决方案（两步）：**

1. **添加 `-Dopensles=enabled`** 到 meson setup 命令
2. **适配 `ao_opensles.c` 为 OHOS API** — mpv 原版使用 `<SLES/OpenSLES_Android.h>`（Android 专有扩展），OHOS 不存在此头文件，且 OHOS 的 OpenSL ES 实现有关键差异：

   | 差异点           | Android/标准                        | OHOS                                                 |
   | ---------------- | ----------------------------------- | ---------------------------------------------------- |
   | BufferQueue 接口 | `SLBufferQueueItf`                  | `SLOHBufferQueueItf`                                 |
   | 接口 ID          | `SL_IID_BUFFERQUEUE`                | `SL_IID_OH_BUFFERQUEUE`                              |
   | 回调签名         | `(SLBufferQueueItf, void*)`         | `(SLOHBufferQueueItf, void*, SLuint32 size)`         |
   | 数据填充方式     | 自行分配 buffer + Enqueue           | `GetBuffer()` 获取系统 buffer → 填数据 → `Enqueue()` |
   | 浮点 PCM         | 支持 (`SLAndroidDataFormat_PCM_EX`) | 不支持，仅 `SL_PCMSAMPLEFORMAT_FIXED_16`             |
   | 头文件           | `OpenSLES_Android.h`                | `OpenSLES_OpenHarmony.h`                             |

   脚本新增 Step 3b (`patch_opensles_for_ohos`) 将 `ao_opensles.c` 替换为 OHOS 适配版本。

### 7.2 播放中 SIGSEGV 崩溃 (signal 11)

**现象：** 使用 OHOS 适配版 OpenSL ES 后，音频可以开始播放，但约 4-5 秒后 app 崩溃，日志显示 `DFX_SignalHandler :: signo(11)` (SIGSEGV)。

**排查过程：**

1. 崩溃发生在 `buffer_callback` 的音频数据写入阶段
2. 逐一排查发现 3 个问题：
   - `resume()` 手动调用 `buffer_callback()` → `GetBuffer()` 在系统未准备好时返回无效指针 → 写入非法内存
   - 使用固定的 `p->bytes_per_enqueue` 大小写入 buffer，但 OHOS `GetBuffer()` 返回的 buffer 大小可能不同 → 缓冲区溢出
   - `init()` 阶段就 `SetPlayState(PLAYING)` 开始播放，系统回调时 mpv 音频管道尚未就绪

**解决方案：**

1. **`start()` 不再手动调 `buffer_callback`** — 只调 `SetPlayState(PLAYING)`，由系统在需要数据时触发回调
2. **使用 `GetBuffer` 返回的实际 buffer 大小** — 根据 `buf_size` 计算帧数 `frames = buf_size / bytes_per_frame`，而非使用预设固定值
3. **`SetPlayState(PLAYING)` 移到 `start()`** — `init()` 只做资源初始化和回调注册，不启动播放
4. **`numBuffers` 从 1 增加到 4** — 减少 buffer 不足导致的竞态

### 7.3 暂停后无法恢复播放

**现象：** 播放正常，暂停后再次播放，音频无声且不再恢复。

**排查过程：**

1. mpv 暂停时会调用 `reset()` → `start()` 恢复
2. `reset()` 中使用了 `SL_PLAYSTATE_STOPPED`
3. OHOS 的 OpenSL ES 在 `STOPPED` 状态会**拆除播放管道**，导致后续 `SetPlayState(PLAYING)` 时系统不再触发数据回调

**解决方案：**

`reset()` 中改用 `SL_PLAYSTATE_PAUSED` 代替 `SL_PLAYSTATE_STOPPED`。`PAUSED` 保持播放管道就绪，恢复 `PLAYING` 后系统继续正常请求数据。

---

## 八、目录结构

```
mpv_audio_kit/
├── ohos/
│   ├── build_ohos_libmpv.sh      ← 编译脚本
│   ├── BUILD_NATIVE_LIBS.md      ← 本文档
│   ├── hvigorfile.ts             ← 含自动编译检测逻辑
│   ├── build-profile.json5
│   ├── oh-package.json5
│   ├── build/                     ← 编译中间目录（不提交）
│   │   ├── ffmpeg-7.1.1/
│   │   ├── libplacebo-7.349.0/
│   │   ├── mpv-0.41.0/
│   │   │   └── sub/osd_libass_stub.c  ← 自动生成的桩实现
│   │   └── install/               ← 编译安装目录
│   │       ├── lib/               ← .a 静态库 + libmpv.so
│   │       └── include/           ← 头文件（含 ass/ 桩头文件）
│   ├── libs/
│   │   └── arm64-v8a/            ← 最终产物
│   │       └── libmpv.so          ← 唯一的 .so 文件（~16MB）
│   └── src/
│       └── main/ets/components/plugin/
│           └── MpvAudioKitPlugin.ets
└── lib/
    └── src/
        ├── mpv_bindings.dart      ← OHOS 平台 DynamicLibrary.open('libmpv.so')
        └── mpv_audio_kit.dart     ← OHOS 平台跳过 setlocale
```
