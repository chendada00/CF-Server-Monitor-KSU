let callbackCounter = 0;

function getUniqueCallbackName(prefix) {
    return `${prefix}_callback_${Date.now()}_${callbackCounter++}`;
}

export function exec(command, options = {}) {
    return new Promise((resolve, reject) => {
        const callbackFuncName =
            getUniqueCallbackName('exec');

        window[callbackFuncName] =
            (errno, stdout, stderr) => {
                try {
                    resolve({
                        errno,
                        stdout,
                        stderr
                    });
                } finally {
                    delete window[callbackFuncName];
                }
            };

        try {
            if (
                typeof window.ksu === 'undefined' ||
                typeof window.ksu.exec !== 'function'
            ) {
                throw new Error(
                    'KernelSU WebUI bridge "ksu.exec" is unavailable'
                );
            }

            window.ksu.exec(
                command,
                JSON.stringify(options),
                callbackFuncName
            );
        } catch (error) {
            delete window[callbackFuncName];
            reject(error);
        }
    });
}

export function toast(message) {
    if (
        typeof window.ksu !== 'undefined' &&
        typeof window.ksu.toast === 'function'
    ) {
        window.ksu.toast(String(message));
    }
}

export function fullScreen(isFullScreen) {
    if (
        typeof window.ksu !== 'undefined' &&
        typeof window.ksu.fullScreen === 'function'
    ) {
        window.ksu.fullScreen(Boolean(isFullScreen));
    }
}

export function enableEdgeToEdge(enable) {
    if (
        typeof window.ksu !== 'undefined' &&
        typeof window.ksu.enableEdgeToEdge === 'function'
    ) {
        window.ksu.enableEdgeToEdge(Boolean(enable));
    }
}

export function moduleInfo() {
    if (
        typeof window.ksu !== 'undefined' &&
        typeof window.ksu.moduleInfo === 'function'
    ) {
        return window.ksu.moduleInfo();
    }

    return null;
}

export function exit() {
    if (
        typeof window.ksu !== 'undefined' &&
        typeof window.ksu.exit === 'function'
    ) {
        window.ksu.exit();
    }
}