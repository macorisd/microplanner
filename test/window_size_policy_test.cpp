#include "../windows/runner/window_size_policy.h"

// Expected physical tracking sizes. DPI scaling must not be applied a second time.
static_assert(HalfMonitorMinimum(1366, 768).width == 683);
static_assert(HalfMonitorMinimum(1366, 768).height == 384);
static_assert(HalfMonitorMinimum(1920, 1080).width == 960);
static_assert(HalfMonitorMinimum(1920, 1080).height == 540);
static_assert(HalfMonitorMinimum(2560, 1440).width == 1280);
static_assert(HalfMonitorMinimum(2560, 1440).height == 720);
static_assert(HalfMonitorMinimum(3840, 2160).width == 1920);
static_assert(HalfMonitorMinimum(3840, 2160).height == 1080);
static_assert(HalfMonitorMinimum(1921, 1081).width == 961);
static_assert(HalfMonitorMinimum(1921, 1081).height == 541);
