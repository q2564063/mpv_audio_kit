// Script for compiling build behavior. It is built in the build plug-in and cannot be modified currently.
import { harTasks } from '@ohos/hvigor-ohos-plugin';
import { execSync } from 'child_process';
import { existsSync } from 'fs';
import { resolve } from 'path';

// Pre-build: ensure native .so files exist
const libDir = resolve(__dirname, 'libs', 'arm64-v8a');
const requiredLib = resolve(libDir, 'libmpv.so');
if (!existsSync(requiredLib)) {
    const script = resolve(__dirname, 'build_ohos_libmpv.sh');
    if (existsSync(script)) {
        console.log('[mpv_audio_kit] libmpv.so not found, running build script...');
        try {
            execSync(`bash "${script}"`, { stdio: 'inherit', cwd: resolve(__dirname, '..') });
        } catch (e) {
            console.error('[mpv_audio_kit] Failed to build native libs. Please run manually: ./ohos/build_ohos_libmpv.sh');
            throw e;
        }
    } else {
        console.warn('[mpv_audio_kit] libmpv.so not found and build script missing. Please build native libs manually.');
    }
}

export default {
    system: harTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins: []         /* Custom plugin to extend the functionality of Hvigor. */
}