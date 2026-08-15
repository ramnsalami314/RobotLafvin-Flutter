import 'package:flutter/material.dart';

import '../screens/radar_screen.dart';


// this is the approutes
class AppRoutes {
  static const String radar = '/radar';

  static Map<String, WidgetBuilder> get routes => {
        radar: (_) => const RadarScreen(),
      };
}