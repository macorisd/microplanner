package com.microplanner.microplanner;

import android.app.Instrumentation;
import android.os.Bundle;
import java.io.PrintWriter;
import java.io.StringWriter;

/** Runs the production headless operation without an Activity or a fake session. */
public class ReminderSyncDeviceTest extends Instrumentation {
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            if (!BackgroundSync.verify(getTargetContext())) {
                throw new IllegalStateException("Headless reminder sync did not complete");
            }
            result.putString("stream", "PASS: reminder worker completed without an Activity\n");
            finish(-1, result);
        } catch (Throwable error) {
            StringWriter trace = new StringWriter();
            error.printStackTrace(new PrintWriter(trace));
            result.putString("stream", "FAIL: " + trace + "\n");
            finish(0, result);
        }
    }
}
