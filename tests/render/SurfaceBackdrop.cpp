#include <render/pass/SurfacePassElement.hpp>

#include <gtest/gtest.h>

static const CBox MONITOR = {1280, 0, 1280, 800};

TEST(SurfaceBackdrop, wallpaperCoveringTheMonitorIsABackdrop) {
    EXPECT_TRUE(CSurfacePassElement::isBackdrop(true, MONITOR, MONITOR, 1.F, false));
    EXPECT_TRUE(CSurfacePassElement::isBackdrop(true, CBox{1270, -10, 1300, 820}, MONITOR, 1.F, false));
}

TEST(SurfaceBackdrop, onlyTheLowestBackgroundLayer) {
    EXPECT_FALSE(CSurfacePassElement::isBackdrop(false, MONITOR, MONITOR, 1.F, false));
}

TEST(SurfaceBackdrop, notWhenTheMonitorShowsAroundIt) {
    EXPECT_FALSE(CSurfacePassElement::isBackdrop(true, CBox{1280, 26, 1280, 774}, MONITOR, 1.F, false));
    EXPECT_FALSE(CSurfacePassElement::isBackdrop(true, CBox{1281, 0, 1279, 800}, MONITOR, 1.F, false));
    EXPECT_FALSE(CSurfacePassElement::isBackdrop(true, CBox{0, 0, 1280, 800}, MONITOR, 1.F, false));
}

TEST(SurfaceBackdrop, notWhileFadingOrBlurred) {
    EXPECT_FALSE(CSurfacePassElement::isBackdrop(true, MONITOR, MONITOR, 0.5F, false));
    EXPECT_FALSE(CSurfacePassElement::isBackdrop(true, MONITOR, MONITOR, 1.F, true));
}
