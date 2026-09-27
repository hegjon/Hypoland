#include <aquamarine/backend/Backend.hpp>
#include "Renderer.hpp"
#include "shared.hpp"

#include <fcntl.h>
#include <format>
#include <string>
#include <unistd.h>

using namespace Aquamarine;
using namespace Hyprutils::Memory;

// Opens the first usable render node, or -1 if the machine has no GPU.
static int openRenderNode() {
    for (int i = 128; i < 136; ++i) {
        const auto PATH = std::format("/dev/dri/renderD{}", i);
        if (int fd = open(PATH.c_str(), O_RDWR | O_CLOEXEC); fd >= 0) {
            std::cout << "Using " << PATH << "\n";
            return fd;
        }
    }

    return -1;
}

int main() {
    // Make the driver report OpenGL ES 2.0 only, which is what pre-GLES3
    // hardware (Intel gen4/4.5/5 under crocus) offers. Must be set before any
    // context is created. Mesa-specific, so a non-Mesa driver simply runs this
    // as a plain "the renderer still initializes" test.
    setenv("MESA_GLES_VERSION_OVERRIDE", "2.0", 1);

    SBackendOptions options;
    options.logFunction = [](eBackendLogLevel level, std::string msg) { std::cout << "[AQ] " << msg << "\n"; };

    SBackendImplementationOptions headless;
    headless.backendType        = AQ_BACKEND_HEADLESS;
    headless.backendRequestMode = AQ_BACKEND_REQUEST_IF_AVAILABLE;

    auto backend = CBackend::create({headless}, options);
    if (!backend) {
        std::cout << "Skipping: no backend\n";
        return 0;
    }

    const int FD = openRenderNode();
    if (FD < 0) {
        std::cout << "Skipping: no render node available\n";
        return 0;
    }

    int ret = 0;

    // The regression: on a GLES2-only driver, both GLES3 rungs of the context
    // fallback ladder fail, and without a 2.0 rung attempt() returns nullptr,
    // which takes the DRM renderer state down with it.
    auto renderer = CDRMRenderer::attempt(backend, FD);
    EXPECT(!!renderer, true);

    close(FD);

    return ret;
}
