#ifndef RUNNER_WINDOW_SIZE_POLICY_H_
#define RUNNER_WINDOW_SIZE_POLICY_H_

// Monitor and tracking sizes are both physical pixels. Do not apply DPI again.
struct WindowMinimum {
  long width;
  long height;
};

constexpr WindowMinimum HalfMonitorMinimum(long width, long height) {
  return {(width + 1) / 2, (height + 1) / 2};
}

#endif  // RUNNER_WINDOW_SIZE_POLICY_H_
