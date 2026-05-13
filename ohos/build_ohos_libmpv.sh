#!/bin/bash
set -euo pipefail

###############################################################################
# build_ohos_libmpv.sh
#
# Cross-compiles FFmpeg (audio-only) + mpv (libmpv, audio-only) for
# OpenHarmony / HarmonyOS arm64-v8a using the OHOS NDK from DevEco Studio.
#
# Usage:
#   chmod +x ohos/build_ohos_libmpv.sh
#   ./ohos/build_ohos_libmpv.sh
#
# Prerequisites (macOS):
#   brew install meson ninja pkg-config nasm
#   DevEco Studio installed at /Applications/DevEco-Studio.app
###############################################################################

# ── Configuration ──────────────────────────────────────────────────────────
OHOS_SDK="${OHOS_SDK:-/Applications/DevEco-Studio.app/Contents/sdk}"
NDK_ROOT="$OHOS_SDK/default/openharmony/native"
TOOLCHAIN="$NDK_ROOT/llvm"
SYSROOT="$NDK_ROOT/sysroot"

TARGET_ARCH="aarch64"
TARGET_TRIPLE="aarch64-linux-ohos"
ABI="arm64-v8a"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/build"
PREFIX="$BUILD_DIR/install"

FFMPEG_VERSION="7.1.1"
MPV_VERSION="0.41.0"
LIBPLACEBO_VERSION="7.349.0"

NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Validate ───────────────────────────────────────────────────────────────
[ -f "$TOOLCHAIN/bin/clang" ] || error "OHOS NDK clang not found at $TOOLCHAIN/bin/clang"
command -v meson  >/dev/null || error "meson not found. Install: brew install meson"
command -v ninja  >/dev/null || error "ninja not found. Install: brew install ninja"
command -v pkg-config >/dev/null || error "pkg-config not found. Install: brew install pkg-config"

info "OHOS NDK: $NDK_ROOT"
info "Build dir: $BUILD_DIR"
info "Install prefix: $PREFIX"

mkdir -p "$BUILD_DIR" "$PREFIX"

# ── Helper: download + extract ─────────────────────────────────────────────
download_extract() {
    local url="$1" dir="$2"
    local filename
    filename="$(basename "$url")"
    if [ ! -d "$dir" ]; then
        if [ ! -f "$BUILD_DIR/$filename" ]; then
            info "Downloading $filename ..."
            curl -L -o "$BUILD_DIR/$filename" "$url"
        fi
        info "Extracting $filename ..."
        tar -xf "$BUILD_DIR/$filename" -C "$BUILD_DIR"
    else
        info "$dir already exists, skipping download."
    fi
}

###############################################################################
# Step 1: Build FFmpeg (audio-only)
###############################################################################
build_ffmpeg() {
    info "========== Building FFmpeg $FFMPEG_VERSION (audio-only) =========="

    download_extract \
        "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
        "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"

    cd "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"

    # Clean previous build if any
    [ -f config.mak ] && make distclean || true

    ./configure \
        --prefix="$PREFIX" \
        --enable-cross-compile \
        --cross-prefix="$TOOLCHAIN/bin/$TARGET_TRIPLE-" \
        --cc="$TOOLCHAIN/bin/clang" \
        --cxx="$TOOLCHAIN/bin/clang++" \
        --ar="$TOOLCHAIN/bin/llvm-ar" \
        --ranlib="$TOOLCHAIN/bin/llvm-ranlib" \
        --strip="$TOOLCHAIN/bin/llvm-strip" \
        --nm="$TOOLCHAIN/bin/llvm-nm" \
        --target-os=linux \
        --arch="$TARGET_ARCH" \
        --sysroot="$SYSROOT" \
        --extra-cflags="--target=$TARGET_TRIPLE --sysroot=$SYSROOT -fPIC" \
        --extra-ldflags="--target=$TARGET_TRIPLE --sysroot=$SYSROOT" \
        --enable-static \
        --disable-shared \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --enable-pthreads \
        --enable-avcodec \
        --enable-avfilter \
        --enable-avformat \
        --enable-avutil \
        --enable-swresample \
        --enable-swscale \
        --disable-avdevice \
        --disable-protocols \
        --enable-protocol=file,http,https,tcp,udp,tls,data,pipe,async,cache,crypto,subfile \
        --enable-demuxers \
        --disable-decoders \
        --enable-decoder=aac,aac_latm,ac3,eac3,alac,ape,dca,flac,mlp,mp1,mp1float,mp2,mp2float,mp3,mp3adu,mp3adufloat,mp3float,mp3on4,mp3on4float,opus,truehd,tta,vorbis,wavpack,wmalossless,wmapro,wmav1,wmav2,wmavoice,mpc7,mpc8,shorten,speex,s302m,atrac3,atrac3p,atrac9,cook,ralf,sipr,nellymoser,gsm,gsm_ms,adpcm_ima_qt,adpcm_ms,dsd_lsbf,dsd_lsbf_planar,dsd_msbf,dsd_msbf_planar,pcm_alaw,pcm_bluray,pcm_dvd,pcm_f16le,pcm_f24le,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le,pcm_lxf,pcm_mulaw,pcm_s16be,pcm_s16be_planar,pcm_s16le,pcm_s16le_planar,pcm_s24be,pcm_s24daud,pcm_s24le,pcm_s24le_planar,pcm_s32be,pcm_s32le,pcm_s32le_planar,pcm_s64be,pcm_s64le,pcm_s8,pcm_s8_planar,pcm_u16be,pcm_u16le,pcm_u24be,pcm_u24le,pcm_u32be,pcm_u32le,pcm_u8,pcm_vidc \
        --disable-encoders \
        --disable-muxers \
        --disable-parsers \
        --enable-parser=aac,aac_latm,ac3,flac,mpegaudio,opus,vorbis,dca,cook \
        --disable-bsfs \
        --enable-bsf=aac_adtstoasc,extract_extradata,null,setts \
        --disable-filters \
        --enable-filter=aformat,amix,anull,aresample,atempo,volume,aeval,pan,channelmap,channelsplit,loudnorm,equalizer,bass,treble,highpass,lowpass,silencedetect,silenceremove,afade,acrossfade,acompressor,alimiter,dynaudnorm,replaygain \
        --disable-outdevs \
        --disable-indevs \
        --disable-iconv \
        --enable-network \
        --enable-version3 \
        --disable-sdl2 \
        --disable-xlib \
        --disable-libdrm \
        --disable-vaapi \
        --disable-vdpau \
        --disable-hwaccels \
        --disable-vulkan \
        --disable-postproc \
        --disable-pixelutils \
        --disable-videotoolbox \
        --disable-audiotoolbox \
        --disable-mediacodec \
        --disable-d3d11va \
        --disable-dxva2 \
        --disable-cuda-llvm \
        --disable-asm \
        --enable-lto=thin

    make -j"$NPROC"
    make install

    info "FFmpeg installed to $PREFIX"
}

###############################################################################
# Step 2: Build libplacebo (static, no GPU backends)
###############################################################################
build_libplacebo() {
    info "========== Building libplacebo v$LIBPLACEBO_VERSION (static, no GPU) =========="

    download_extract \
        "https://github.com/haasn/libplacebo/archive/refs/tags/v${LIBPLACEBO_VERSION}.tar.gz" \
        "$BUILD_DIR/libplacebo-${LIBPLACEBO_VERSION}"

    cd "$BUILD_DIR/libplacebo-${LIBPLACEBO_VERSION}"

    # Download fast_float submodule (GitHub tarballs don't include submodules)
    if [ ! -f "3rdparty/fast_float/include/fast_float/fast_float.h" ]; then
        info "Downloading fast_float ..."
        rm -rf 3rdparty/fast_float
        curl -sL "https://github.com/fastfloat/fast_float/archive/refs/tags/v6.1.1.tar.gz" | tar xz -C 3rdparty
        mv 3rdparty/fast_float-6.1.1 3rdparty/fast_float
    fi

    rm -rf build-ohos

    # Reuse the same cross file format
    cat > ohos-cross.ini << CROSSEOF
[binaries]
c = '$TOOLCHAIN/bin/clang'
cpp = '$TOOLCHAIN/bin/clang++'
ar = '$TOOLCHAIN/bin/llvm-ar'
strip = '$TOOLCHAIN/bin/llvm-strip'
ranlib = '$TOOLCHAIN/bin/llvm-ranlib'
pkg-config = '$(which pkg-config)'

[built-in options]
c_args = ['--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT', '-fPIC']
c_link_args = ['--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT']
cpp_args = ['--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT', '-fPIC']
cpp_link_args = ['--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT']

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
sys_root = '$SYSROOT'
CROSSEOF

    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
    PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="" \
    meson setup build-ohos \
        --cross-file ohos-cross.ini \
        --prefix="$PREFIX" \
        --default-library=static \
        -Dvulkan=disabled \
        -Dopengl=disabled \
        -Dd3d11=disabled \
        -Dshaderc=disabled \
        -Dglslang=disabled \
        -Dlcms=disabled \
        -Dunwind=disabled \
        -Ddemos=false \
        -Dtests=false \
        -Dbench=false \
        -Dfuzz=false

    ninja -C build-ohos -j"$NPROC"
    ninja -C build-ohos install

    info "libplacebo installed to $PREFIX"
}

###############################################################################
# Step 3: Patch mpv meson.build for audio-only (remove libass dependency)
###############################################################################
patch_mpv_for_audio_only() {
    info "Patching mpv for audio-only build (libass stubs) ..."

    # Create stub ass headers so unguarded #include <ass/ass.h> compiles.
    mkdir -p "$PREFIX/include/ass"
    cat > "$PREFIX/include/ass/ass.h" << 'STUBEOF'
#ifndef ASS_ASS_H
#define ASS_ASS_H
#include <stdint.h>
typedef struct ass_library ASS_Library;
typedef struct ass_renderer ASS_Renderer;
typedef struct ass_track ASS_Track;
typedef struct ass_image ASS_Image;
typedef struct ass_event ASS_Event;
typedef struct ass_style ASS_Style;
static inline int64_t ass_library_version(void) { return 0; }
#endif
STUBEOF
    cat > "$PREFIX/include/ass/ass_types.h" << 'STUBEOF'
#ifndef ASS_TYPES_H
#define ASS_TYPES_H
#include "ass.h"
#endif
STUBEOF

    # Create fake libass.pc
    cat > "$PREFIX/lib/pkgconfig/libass.pc" << PCEOF
prefix=$PREFIX
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: libass
Description: stub libass for audio-only mpv build
Version: 0.17.0
Cflags: -I\${includedir}
PCEOF

    # Create stub C file with all exported functions from the 3 removed files
    # (osd_libass.c, ass_mp.c, sd_ass.c) that are referenced elsewhere
    cat > "$BUILD_DIR/mpv-${MPV_VERSION}/sub/osd_libass_stub.c" << 'STUBCEOF'
/* Stub implementations for libass-dependent functions removed for audio-only. */
#include <stddef.h>
#include <string.h>
#include "osd.h"
#include "osd_state.h"
#include "sd.h"
#include "options/m_option.h"

void osd_destroy_backend(struct osd_state *osd) { (void)osd; }

void osd_get_function_sym(char *buffer, size_t buffer_size, int osd_function) {
    (void)osd_function;
    if (buffer && buffer_size > 0) buffer[0] = '\0';
}

void osd_mangle_ass(bstr *dst, const char *in, bool replace_newlines) {
    (void)dst; (void)in; (void)replace_newlines;
}

void osd_get_text_size(struct osd_state *osd, int *out_screen_h, int *out_font_h) {
    (void)osd;
    if (out_screen_h) *out_screen_h = 0;
    if (out_font_h) *out_font_h = 0;
}

void osd_set_external(struct osd_state *osd, struct osd_external_ass *ov) {
    (void)osd; (void)ov;
}

void osd_set_external_remove_owner(struct osd_state *osd, void *owner) {
    (void)osd; (void)owner;
}

struct sub_bitmaps *osd_object_get_bitmaps(struct osd_state *osd,
                                           struct osd_object *obj, int format) {
    (void)osd; (void)obj; (void)format;
    return NULL;
}

int sd_ass_fmt_offset(const char *evt_fmt) {
    (void)evt_fmt;
    return 0;
}

bstr sd_ass_pkt_text(struct sd_filter *ft, struct demux_packet *pkt, int offset) {
    (void)ft; (void)pkt; (void)offset;
    return (bstr){NULL, 0};
}

bstr sd_ass_to_plaintext(char **out, const char *in) {
    (void)out; (void)in;
    return (bstr){NULL, 0};
}

/* sd_ass driver stub - referenced from dec_sub.c */
const struct sd_functions sd_ass = {
    .name = "ass",
};

/* mp_sub_filter_opts stub - referenced from options.c */
#define OPT_BASE_STRUCT struct mp_sub_filter_opts
const struct m_sub_options mp_sub_filter_opts = {
    .opts = (const struct m_option[]){ {0} },
    .size = sizeof(struct mp_sub_filter_opts),
};
#undef OPT_BASE_STRUCT
STUBCEOF

    info "Created osd_libass_stub.c"

    # Patch meson.build: remove libass .c files, add stub
    python3 << 'PYEOF'
import re

with open('meson.build', 'r') as f:
    content = f.read()

# Remove libass source files from unconditional sources
for f in ['sub/ass_mp.c', 'sub/osd_libass.c', 'sub/sd_ass.c']:
    pattern = r"\s*'" + re.escape(f) + r"',?\n"
    content = re.sub(pattern, '\n', content)

# Add stub file after 'sub/osd.c'
content = content.replace(
    "'sub/osd.c',",
    "'sub/osd.c',\n    'sub/osd_libass_stub.c',"
)

with open('meson.build', 'w') as f:
    f.write(content)

print('Patched meson.build: replaced libass files with stub')
PYEOF
}

###############################################################################
# Step 3b: Patch ao_opensles.c for OHOS (use OH-specific BufferQueue API)
###############################################################################
patch_opensles_for_ohos() {
    info "Patching ao_opensles.c for OHOS compatibility ..."

    local AO_FILE="$BUILD_DIR/mpv-${MPV_VERSION}/audio/out/ao_opensles.c"

    # OHOS OpenSL ES key differences from Android/standard:
    #   1. No OpenSLES_Android.h — no float PCM, no AndroidConfiguration
    #   2. Must use SLOHBufferQueueItf (from OpenSLES_OpenHarmony.h)
    #      instead of standard SLBufferQueueItf
    #   3. Must use SL_IID_OH_BUFFERQUEUE instead of SL_IID_BUFFERQUEUE
    #   4. Callback signature: (SLOHBufferQueueItf, void*, SLuint32 size)
    #   5. Must call GetBuffer() to obtain writable buffer, then Enqueue()
    #   6. Do NOT manually invoke the callback — system triggers it after
    #      SetPlayState(PLAYING)
    # Reference: OpenHarmony docs "使用OpenSL ES开发音频播放功能"

    cat > "$AO_FILE" << 'OPENSLES_OHOS_EOF'
/*
 * OpenSL ES audio output driver — OHOS (OpenHarmony) adaptation.
 * Based on the original Android OpenSL ES driver by Ilya Zhuravlev.
 *
 * OHOS only supports a subset of OpenSL ES 1.0.1 with OH-specific extensions:
 *   - SLOHBufferQueueItf replaces SLBufferQueueItf
 *   - SL_IID_OH_BUFFERQUEUE replaces SL_IID_BUFFERQUEUE
 *   - No float PCM support (integer S16 only)
 *   - Callback: system calls it when buffer is needed; use GetBuffer+Enqueue
 *
 * This file is part of mpv.
 *
 * mpv is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#include "ao.h"
#include "internal.h"
#include "common/msg.h"
#include "audio/format.h"
#include "options/m_option.h"
#include "osdep/threads.h"
#include "osdep/timer.h"

#include <SLES/OpenSLES.h>
#include <SLES/OpenSLES_OpenHarmony.h>
#include <SLES/OpenSLES_Platform.h>

struct priv {
    SLObjectItf sl, output_mix, player;
    SLOHBufferQueueItf buffer_queue;
    SLEngineItf engine;
    SLPlayItf play;
    mp_mutex buffer_lock;

    int bytes_per_frame;
    int buffer_size_in_ms;
};

#define DESTROY(thing) \
    if (p->thing) { \
        (*p->thing)->Destroy(p->thing); \
        p->thing = NULL; \
    }

static void uninit(struct ao *ao)
{
    struct priv *p = ao->priv;

    if (p->play)
        (*p->play)->SetPlayState(p->play, SL_PLAYSTATE_STOPPED);

    DESTROY(player);
    DESTROY(output_mix);
    DESTROY(sl);

    p->buffer_queue = NULL;
    p->engine = NULL;
    p->play = NULL;

    mp_mutex_destroy(&p->buffer_lock);
}

#undef DESTROY

static void buffer_callback(SLOHBufferQueueItf buffer_queue, void *context,
                             SLuint32 size)
{
    struct ao *ao = context;
    struct priv *p = ao->priv;

    mp_mutex_lock(&p->buffer_lock);

    /* OHOS pattern: GetBuffer → fill → Enqueue */
    SLuint8 *buf = NULL;
    SLuint32 buf_size = 0;
    SLresult res = (*buffer_queue)->GetBuffer(buffer_queue, &buf, &buf_size);
    if (res != SL_RESULT_SUCCESS || !buf || buf_size == 0) {
        mp_mutex_unlock(&p->buffer_lock);
        return;
    }

    /* Use the actual buffer size from GetBuffer, not our own calculation */
    int frames = (int)(buf_size / (SLuint32)p->bytes_per_frame);
    if (frames <= 0) {
        mp_mutex_unlock(&p->buffer_lock);
        return;
    }

    double delay = frames / (double)ao->samplerate;
    void *buf_ptr = (void *)buf;
    ao_read_data(ao, &buf_ptr, frames,
        mp_time_ns() + MP_TIME_S_TO_NS(delay), NULL, true, true);

    res = (*buffer_queue)->Enqueue(buffer_queue, buf, buf_size);
    if (res != SL_RESULT_SUCCESS)
        MP_ERR(ao, "Failed to Enqueue: %ld\n", (long)res);

    mp_mutex_unlock(&p->buffer_lock);
}

#define CHK(stmt) \
    { \
        SLresult res = stmt; \
        if (res != SL_RESULT_SUCCESS) { \
            MP_ERR(ao, "%s: %ld\n", #stmt, (long)res); \
            goto error; \
        } \
    }

static int init(struct ao *ao)
{
    struct priv *p = ao->priv;
    SLDataLocator_BufferQueue locator_buffer_queue;
    SLDataLocator_OutputMix locator_output_mix;
    SLDataFormat_PCM pcm;
    SLDataSource audio_source;
    SLDataSink audio_sink;

    /* OHOS supports stereo */
    mp_chmap_from_channels(&ao->channels, 2);
    ao->samplerate = MPCLAMP(ao->samplerate, 8000, 192000);

    /* OHOS: integer PCM only, S16 */
    ao->format = AF_FORMAT_S16;
    p->bytes_per_frame = ao->channels.num * af_fmt_to_bytes(ao->format);

    CHK(slCreateEngine(&p->sl, 0, NULL, 0, NULL, NULL));
    CHK((*p->sl)->Realize(p->sl, SL_BOOLEAN_FALSE));
    CHK((*p->sl)->GetInterface(p->sl, SL_IID_ENGINE, (void*)&p->engine));
    CHK((*p->engine)->CreateOutputMix(p->engine, &p->output_mix, 0, NULL, NULL));
    CHK((*p->output_mix)->Realize(p->output_mix, SL_BOOLEAN_FALSE));

    locator_buffer_queue.locatorType = SL_DATALOCATOR_BUFFERQUEUE;
    locator_buffer_queue.numBuffers = 4;

    pcm.formatType = SL_DATAFORMAT_PCM;
    pcm.numChannels = ao->channels.num;
    pcm.bitsPerSample = SL_PCMSAMPLEFORMAT_FIXED_16;
    pcm.containerSize = 16;
    pcm.channelMask = SL_SPEAKER_FRONT_LEFT | SL_SPEAKER_FRONT_RIGHT;
    pcm.endianness = SL_BYTEORDER_LITTLEENDIAN;
    pcm.samplesPerSec = ao->samplerate * 1000;

    if (p->buffer_size_in_ms) {
        ao->device_buffer = ao->samplerate * p->buffer_size_in_ms / 1000;
        ao->def_buffer = 0;
    }

    int r = mp_mutex_init(&p->buffer_lock);
    if (r) {
        MP_ERR(ao, "Failed to initialize the mutex: %d\n", r);
        goto error;
    }

    audio_source.pFormat = (void*)&pcm;
    audio_source.pLocator = (void*)&locator_buffer_queue;

    locator_output_mix.locatorType = SL_DATALOCATOR_OUTPUTMIX;
    locator_output_mix.outputMix = p->output_mix;

    audio_sink.pLocator = (void*)&locator_output_mix;
    audio_sink.pFormat = NULL;

    /* OHOS: pass 0 interfaces; obtain SL_IID_OH_BUFFERQUEUE after Realize */
    CHK((*p->engine)->CreateAudioPlayer(p->engine, &p->player, &audio_source,
        &audio_sink, 0, NULL, NULL));

    CHK((*p->player)->Realize(p->player, SL_BOOLEAN_FALSE));
    CHK((*p->player)->GetInterface(p->player, SL_IID_PLAY, (void*)&p->play));

    /* OHOS: must use SL_IID_OH_BUFFERQUEUE */
    CHK((*p->player)->GetInterface(p->player, SL_IID_OH_BUFFERQUEUE,
        (void*)&p->buffer_queue));
    CHK((*p->buffer_queue)->RegisterCallback(p->buffer_queue,
        buffer_callback, ao));

    /* Do NOT start playing here — wait for start() so mpv's audio
     * pipeline is ready to supply data when the callback fires. */

    return 1;
error:
    uninit(ao);
    return -1;
}

#undef CHK

static void reset(struct ao *ao)
{
    struct priv *p = ao->priv;
    /* OHOS: use PAUSED instead of STOPPED.
     * STOPPED may fully tear down the playback pipeline, preventing
     * the system from re-triggering callbacks on subsequent PLAYING. */
    (*p->play)->SetPlayState(p->play, SL_PLAYSTATE_PAUSED);
    (*p->buffer_queue)->Clear(p->buffer_queue);
}

static void start(struct ao *ao)
{
    struct priv *p = ao->priv;
    /* OHOS: system will invoke buffer_callback when it needs data */
    (*p->play)->SetPlayState(p->play, SL_PLAYSTATE_PLAYING);
}

#define OPT_BASE_STRUCT struct priv

const struct ao_driver audio_out_opensles = {
    .description = "OpenSL ES audio output",
    .name      = "opensles",
    .init      = init,
    .uninit    = uninit,
    .reset     = reset,
    .start     = start,

    .priv_size = sizeof(struct priv),
    .priv_defaults = &(const struct priv) {
        .buffer_size_in_ms = 250,
    },
    .options = (const struct m_option[]) {
        {"buffer-size-in-ms", OPT_INT(buffer_size_in_ms),
            M_RANGE(0, 500)},
        {0}
    },
    .options_prefix = "opensles",
};
OPENSLES_OHOS_EOF

    info "Patched ao_opensles.c for OHOS (OH BufferQueue API)"
}

###############################################################################
# Step 4: Build mpv (libmpv only, audio-only)
###############################################################################
build_mpv() {
    info "========== Building mpv $MPV_VERSION (libmpv, audio-only) =========="

    download_extract \
        "https://github.com/mpv-player/mpv/archive/refs/tags/v${MPV_VERSION}.tar.gz" \
        "$BUILD_DIR/mpv-${MPV_VERSION}"

    cd "$BUILD_DIR/mpv-${MPV_VERSION}"

    # Patch for audio-only build
    patch_mpv_for_audio_only

    # Patch OpenSL ES for OHOS compatibility
    patch_opensles_for_ohos

    # Remove old build directory if exists
    rm -rf build-ohos

    # Create Meson cross-compilation file
    cat > ohos-cross.ini << CROSSEOF
[binaries]
c = '$TOOLCHAIN/bin/clang'
cpp = '$TOOLCHAIN/bin/clang++'
ar = '$TOOLCHAIN/bin/llvm-ar'
strip = '$TOOLCHAIN/bin/llvm-strip'
ranlib = '$TOOLCHAIN/bin/llvm-ranlib'
pkg-config = '$(which pkg-config)'

[built-in options]
c_args = ['--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT', '-fPIC', '-I$PREFIX/include']
c_link_args = ['--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT', '-L$PREFIX/lib', '-L$TOOLCHAIN/lib/$TARGET_TRIPLE', '-lc++_static', '-lc++abi']
cpp_args = ['--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT', '-fPIC', '-I$PREFIX/include']
cpp_link_args = ['--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT', '-L$PREFIX/lib', '-L$TOOLCHAIN/lib/$TARGET_TRIPLE', '-lc++_static', '-lc++abi']

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
sys_root = '$SYSROOT'
pkg_config_libdir = '$PREFIX/lib/pkgconfig'
CROSSEOF

    info "Cross file created: ohos-cross.ini"

    # Configure with Meson
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
    PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="" \
    meson setup build-ohos \
        --cross-file ohos-cross.ini \
        --prefix="$PREFIX" \
        --default-library=shared \
        -Dauto_features=disabled \
        -Dgpl=true \
        -Dlibmpv=true \
        -Dcplayer=false \
        -Dbuild-date=false \
        -Dtests=false \
        -Dgl=disabled \
        -Dplain-gl=disabled \
        -Dopensles=enabled \
        -Dzlib=enabled \
        -Db_lto=true

    ninja -C build-ohos -j"$NPROC"
    ninja -C build-ohos install

    info "mpv (libmpv) installed to $PREFIX"
}

###############################################################################
# Step 5: Collect outputs
###############################################################################
collect_outputs() {
    info "========== Collecting .so files =========="

    local OUT_DIR="$SCRIPT_DIR/libs/$ABI"
    mkdir -p "$OUT_DIR"

    # Copy libmpv (FFmpeg + libplacebo are statically linked in)
    local mpv_so
    mpv_so=$(find "$PREFIX/lib" -name "libmpv.so*" -not -type l | head -1)
    if [ -z "$mpv_so" ]; then
        error "libmpv.so not found in $PREFIX/lib"
    fi
    cp -v "$mpv_so" "$OUT_DIR/libmpv.so"

    info ""
    info "========== Build complete! =========="
    info "Output files in $OUT_DIR:"
    ls -lh "$OUT_DIR/"
    info ""
    info "libmpv.so contains FFmpeg and libplacebo statically linked."
}

###############################################################################
# Main
###############################################################################
build_ffmpeg
build_libplacebo
build_mpv
collect_outputs

info "Done! You can now run your Flutter OHOS app."
