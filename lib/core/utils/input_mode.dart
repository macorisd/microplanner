import 'package:flutter/material.dart';

/// Touch platforms cannot rely on mouse hover to expose essential controls.
bool usesTouchControls(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
