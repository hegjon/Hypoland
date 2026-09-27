#include <aquamarine/output/Output.hpp>
#include <aquamarine/backend/Backend.hpp>
#include <hyprutils/memory/SharedPtr.hpp>
#include "OutputTiming.hpp"
#include "shared.hpp"

using namespace Aquamarine;
using namespace Hyprutils::Memory;

class CTestOutput : public IOutput {
  public:
    virtual bool commit() {
        return false;
    }

    virtual bool test() {
        return false;
    }

    virtual CSharedPointer<IBackendImplementation> getBackend() {
        return nullptr;
    }

    virtual std::vector<SDRMFormat> getRenderFormats() {
        return {};
    }

    virtual bool pendingPageFlip() {
        return false;
    }

    virtual bool pendingIdleFrame() {
        return false;
    }
};

int main() {
    int         ret = 0;
    CTestOutput output;

    EXPECT(output.hasCursorPlane(), false);
    EXPECT(output.nextVBlank().has_value(), false);

    using namespace std::chrono_literals;

    const auto NEXT = OutputTiming::predictNextVBlank(100ns, 150ns, 100ns);
    EXPECT(NEXT.has_value(), true);
    EXPECT(NEXT->count(), 200);

    EXPECT(OutputTiming::predictNextVBlank(100ns, 200ns, 100ns).has_value(), false);
    EXPECT(OutputTiming::predictNextVBlank(201ns, 200ns, 100ns).has_value(), false);
    EXPECT(OutputTiming::predictNextVBlank(100ns, 150ns, 0ns).has_value(), false);
    EXPECT(OutputTiming::predictNextVBlank(std::chrono::nanoseconds::max() - 50ns, std::chrono::nanoseconds::max() - 25ns, 100ns).has_value(), false);

    const auto STEADY_EPOCH = std::chrono::steady_clock::time_point{};
    const auto CONVERTED    = OutputTiming::toSteadyClock(200ns, 150ns, STEADY_EPOCH + 100ns, STEADY_EPOCH + 110ns);
    EXPECT(CONVERTED.has_value(), true);
    EXPECT(CONVERTED->time_since_epoch().count(), 155);
    EXPECT(OutputTiming::toSteadyClock(160ns, 150ns, STEADY_EPOCH + 100ns, STEADY_EPOCH + 120ns).has_value(), false);

    return ret;
}
