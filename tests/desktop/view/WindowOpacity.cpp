#include <desktop/view/window/WindowPresentation.hpp>

#include <gtest/gtest.h>

using Desktop::View::opaqueAlpha;

TEST(WindowOpacity, nearlyOpaqueIsOpaque) {
    EXPECT_EQ(opaqueAlpha(0.98F), 1.F);
    EXPECT_EQ(opaqueAlpha(0.985F), 1.F);
    EXPECT_EQ(opaqueAlpha(1.F), 1.F);
}

TEST(WindowOpacity, lowerOpacityIsKept) {
    EXPECT_EQ(opaqueAlpha(0.979F), 0.979F);
    EXPECT_EQ(opaqueAlpha(0.96F), 0.96F);
    EXPECT_EQ(opaqueAlpha(0.5F), 0.5F);
    EXPECT_EQ(opaqueAlpha(0.F), 0.F);
}
