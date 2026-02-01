import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

import 'mobile_app.dart';
import 'desktop_app.dart';

void main() {
  runApp(const TortoiseShareApp());
}

class TortoiseShareApp extends StatelessWidget {
  const TortoiseShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TortoiseShare',
      theme: ThemeData(primarySwatch: Colors.green),
      home: _getHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }

  Widget _getHomeScreen() {
    if (defaultTargetPlatform == TargetPlatform.android || 
        defaultTargetPlatform == TargetPlatform.iOS) {
      return MobileApp(); // Application mobile
    } else {
      return DesktopApp(); // Application desktop (PC)
    }
  }
}