#include <render/gl/blur/Aurora.hpp>
#include <render/gl/blur/Kawase.hpp>
#include <render/gl/blur/Glass.hpp>
#include <render/gl/blur/HeatShimmer.hpp>
#include <render/gl/blur/Haze.hpp>
#include <render/ShaderLoader.hpp>

#include <gtest/gtest.h>

using namespace Render::GL;

TEST(BlurMaterial, DefaultUsesPlainFinish) {
    const CDefaultBlurMaterial material;
    const auto                 requirements = material.requirements();

    EXPECT_EQ(material.type(), Render::eBlurType::BLUR_DUAL_KAWASE);
    EXPECT_EQ(requirements.finishFragment, Render::SH_FRAG_BLURFINISH);
    EXPECT_FALSE(requirements.preparedInput);
    EXPECT_FALSE(requirements.liveBlur);
    EXPECT_FALSE(material.isAnimated());
    EXPECT_EQ(material.blurSizeForDamage(100), 40);
    EXPECT_FLOAT_EQ(material.sampleRadius(), 0.F);
}

TEST(BlurMaterial, GlassCapabilitiesAreConfiguredByMaterial) {
    const CGlassBlurMaterial frost(Render::eBlurType::BLUR_FROST, Render::SH_FRAG_FROSTFINISH);
    const auto               frostRequirements = frost.requirements();
    EXPECT_EQ(frost.type(), Render::eBlurType::BLUR_FROST);
    EXPECT_EQ(frostRequirements.finishFragment, Render::SH_FRAG_FROSTFINISH);
    EXPECT_FALSE(frostRequirements.preparedInput);
}

TEST(BlurMaterial, HeatShimmerUsesAnimatedGlassFinish) {
    const CHeatShimmerBlurMaterial heatShimmer;
    const auto                     requirements = heatShimmer.requirements();

    EXPECT_EQ(heatShimmer.type(), Render::eBlurType::BLUR_HEAT_SHIMMER);
    EXPECT_EQ(requirements.finishFragment, Render::SH_FRAG_HEATSHIMMERFINISH);
    EXPECT_FALSE(requirements.preparedInput);
    EXPECT_FALSE(requirements.liveBlur);
}

TEST(BlurMaterial, AuroraUsesAnimatedGlassFinish) {
    const CAuroraBlurMaterial aurora;
    const auto                requirements = aurora.requirements();

    EXPECT_EQ(aurora.type(), Render::eBlurType::BLUR_AURORA);
    EXPECT_EQ(requirements.finishFragment, Render::SH_FRAG_AURORAFINISH);
    EXPECT_FALSE(requirements.preparedInput);
    EXPECT_FALSE(requirements.liveBlur);
}

TEST(BlurMaterial, HazeUsesStaticPearlescentFinish) {
    const CHazeBlurMaterial haze;
    const auto              requirements = haze.requirements();

    EXPECT_EQ(haze.type(), Render::eBlurType::BLUR_HAZE);
    EXPECT_EQ(requirements.finishFragment, Render::SH_FRAG_HAZEFINISH);
    EXPECT_FALSE(requirements.preparedInput);
    EXPECT_FALSE(requirements.liveBlur);
    EXPECT_FALSE(haze.isAnimated());
    EXPECT_EQ(haze.blurSizeForDamage(100), 40);
    EXPECT_FLOAT_EQ(haze.sampleRadius(), 0.F);
}

TEST(BlurDamage, DualKawaseUsesOperationalMinimums) {
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(0, 0), 2.F);
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(-10, -10), 2.F);
}

TEST(BlurDamage, DualKawaseCalculatesConfiguredRadius) {
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(8, 1), 16.F);
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(8, 2), 48.F);
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(12, 3), 168.F);
}

TEST(BlurDamage, DualKawaseUsesOperationalMaximums) {
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(40, 8), 20400.F);
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(100, 10), 51000.F);
}

TEST(BlurDamage, GlassIncludesRefractionReach) {
    EXPECT_FLOAT_EQ(glassDamageRadius(8, 1, 3.F), 19.F);
    EXPECT_FLOAT_EQ(glassDamageRadius(12, 3, 4.25F), 173.F);
}

TEST(BlurDamage, GlassClampsRefractionReach) {
    EXPECT_FLOAT_EQ(glassDamageRadius(8, 1, -1.F), 16.F);
    EXPECT_FLOAT_EQ(glassDamageRadius(8, 1, 100.F), 36.F);
}
