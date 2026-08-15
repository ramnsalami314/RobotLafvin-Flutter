import 'package:flutter/material.dart';

import 'routes/app_routes.dart';

void main() {
  runApp(const LafvinRobotApp());
}

class LafvinRobotApp extends StatelessWidget {
  const LafvinRobotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LAFVIN Robot',
      theme: ThemeData.dark(),
      initialRoute: AppRoutes.radar,
      routes: AppRoutes.routes,
    );
  }
}