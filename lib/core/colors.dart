import 'package:flutter/material.dart';

// Palette de couleurs TortoiseShare 🐢 - Inspirée de la carapace dorée
class AppColors {
  // Couleurs principales - Orange/doré de la carapace avec blanc dominant
  static const Color primary = Color(0xFFFF8F00);      // Orange doré carapace
  static const Color secondary = Color(0xFFFFF3E0);    // Orange très clair
  static const Color accent = Color(0xFFE65100);       // Orange foncé
  static const Color shell = Color(0xFFFFB74D);        // Orange moyen
  static const Color green = Color(0xFF8BC34A);        // Vert tortue (accents)
  
  // Backgrounds - Dominance blanche
  static const Color background = Colors.white;        // Blanc pur
  static const Color backgroundLight = Color(0xFFFAFAFA); // Blanc cassé
  static const Color card = Colors.white;              // Cartes blanches
  static const Color surface = Color(0xFFFFF8F0);      // Surface crème légère
  
  // Texte
  static const Color textPrimary = Color(0xFF2E2E2E);  // Gris foncé
  static const Color textSecondary = Color(0xFF757575); // Gris moyen
  static const Color textLight = Color(0xFF9E9E9E);    // Gris clair
  
  // Status
  static const Color success = Color(0xFF4CAF50);      // Vert pour succès
  static const Color error = Color(0xFFFF5722);        // Orange-rouge pour erreurs (cohérent avec le thème)
  static const Color warning = Color(0xFFFF8F00);      // Orange principal pour warnings
  static const Color info = Color(0xFF2196F3);         // Bleu pour info
  
  // Bordures et dividers
  static const Color border = Color(0xFFE0E0E0);       // Bordure légère
  static const Color divider = Color(0xFFEEEEEE);      // Séparateur
}
