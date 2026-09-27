#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include "../render/gl/GLES2.hpp"
#include "math/Math.hpp"
#include <aquamarine/backend/Misc.hpp>

using DRMFormat = uint32_t;
using SHMFormat = uint32_t;

using SDRMFormat = Aquamarine::SDRMFormat;

namespace NFormatUtils {
    SHMFormat   drmToShm(DRMFormat drm);
    DRMFormat   shmToDRM(SHMFormat shm);
    bool        isFormatYUV(uint32_t drmFormat);
    bool        isShmBufferLayoutValid(DRMFormat drmFormat, const Vector2D& size, int32_t stride, int32_t offset, size_t poolSize);
    std::string drmFormatName(DRMFormat drm);
    std::string drmModifierName(uint64_t mod);
    DRMFormat   alphaFormat(DRMFormat prevFormat);
};
