#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include "../shared.hpp"
#include "tests.hpp"

TEST_CASE(luaDispatcherStrings) {
    OK(getFromSocket("/eval B = hl.bind('SUPER + F24', hl.dsp.exec_cmd('true'))"));
    EXPECT(getFromSocket("/repl return B.handler"), "HL.Dispatcher(exec_cmd)");
    OK(getFromSocket("/eval B:unbind()"));

    OK(getFromSocket("/eval B = hl.bind('SUPER + F24', hl.dsp.window.close())"));
    EXPECT(getFromSocket("/repl return B.handler"), "HL.Dispatcher(close)");
    OK(getFromSocket("/eval B:unbind()"));

    OK(getFromSocket("/eval B = hl.bind('SUPER + F24', function() hl.exec_cmd('true') end)"));
    EXPECT_STARTS_WITH(getFromSocket("/repl return B.handler"), "function: ");
    OK(getFromSocket("/eval B:unbind()"));
}
