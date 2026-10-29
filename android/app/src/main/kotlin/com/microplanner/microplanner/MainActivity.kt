package com.microplanner.microplanner

import io.flutter.embedding.android.FlutterActivity
import android.os.Build
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Flutter already painted its loader; a native fade would overlap two moving logos.
            splashScreen.setOnExitAnimationListener { view -> view.remove() }
        }
    }
}
