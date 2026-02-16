#!/usr/bin/env python3
"""
Script pour ajouter des marges au logo pour éviter qu'il soit coupé
sur les icônes adaptatives Android
"""

from PIL import Image
import os

def add_padding_to_logo(input_path, output_path, padding_percent=25):
    """
    Ajoute des marges transparentes autour du logo
    
    Args:
        input_path: Chemin du logo original
        output_path: Chemin du logo avec marges
        padding_percent: Pourcentage de marge (25 = 25% de chaque côté)
    """
    # Ouvrir l'image
    img = Image.open(input_path)
    
    # Convertir en RGBA si nécessaire
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # Calculer la nouvelle taille avec padding
    original_width, original_height = img.size
    padding = int(max(original_width, original_height) * (padding_percent / 100))
    
    new_width = original_width + (padding * 2)
    new_height = original_height + (padding * 2)
    
    # Créer une nouvelle image avec fond transparent
    new_img = Image.new('RGBA', (new_width, new_height), (255, 255, 255, 0))
    
    # Coller l'image originale au centre
    new_img.paste(img, (padding, padding), img if img.mode == 'RGBA' else None)
    
    # Sauvegarder
    new_img.save(output_path, 'PNG')
    print(f"✅ Logo avec marges créé: {output_path}")
    print(f"   Taille originale: {original_width}x{original_height}")
    print(f"   Nouvelle taille: {new_width}x{new_height}")
    print(f"   Marge: {padding}px de chaque côté")

if __name__ == '__main__':
    input_logo = 'assets/icons/logo.jpg'
    output_logo = 'assets/icons/logo_padded.png'
    
    if not os.path.exists(input_logo):
        print(f"❌ Erreur: {input_logo} n'existe pas")
        exit(1)
    
    # Créer le logo avec 25% de marge
    add_padding_to_logo(input_logo, output_logo, padding_percent=25)
    
    print("\n📝 Prochaines étapes:")
    print("1. Modifier pubspec.yaml pour utiliser logo_padded.png")
    print("2. Lancer: flutter pub run flutter_launcher_icons")
    print("3. Rebuild l'app: flutter clean && flutter build apk")
