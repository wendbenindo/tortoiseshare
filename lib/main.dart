import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

import 'core/colors.dart';
import 'screens/mobile_screen.dart';
import 'screens/desktop_screen.dart';

void main() {
  runApp(const TortoiseShareApp());
}

class TortoiseShareApp extends StatelessWidget {
  const TortoiseShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TortoiseShare',
      theme: ThemeData(
        primarySwatch: Colors.green,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        cardTheme: CardThemeData(
          color: AppColors.card,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: _getHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }

  Widget _getHomeScreen() {
    if (defaultTargetPlatform == TargetPlatform.android || 
        defaultTargetPlatform == TargetPlatform.iOS) {
      return const MobileScreen(); // Application mobile refactorisée
    } else {
      return const DesktopScreen(); // Application desktop refactorisée
    }
  }
}
