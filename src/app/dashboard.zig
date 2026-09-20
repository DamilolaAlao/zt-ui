// ============================================================================
// zt-ui-dashboard - Dashboard component for overview and monitoring
// ============================================================================

const std = @import("std");
const App = struct {
    // References to other components
    model: AnyObject,
    audio_panel: ?DrawPanel,
    state: ?AudioSequenceState,
    frame: ?AudioFrame,
};

pub fn main() !void {
    let app = App{};
    app.init();
    app.run();
}
