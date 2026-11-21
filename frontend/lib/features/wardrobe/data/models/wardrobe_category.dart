import 'package:flutter/material.dart';
import 'package:smartfit/features/recommendation/data/models/product_recommendation_model.dart';

/// Filter chips on the wardrobe (spec §23.19). Decided from the product's
/// category and title; Eastern is checked first so a "lawn shirt" or a
/// "kurta" lands in Eastern, not Tops.
enum WardrobeCategory {
  eastern('Eastern', Icons.auto_awesome_rounded),
  dresses('Dresses', Icons.checkroom_rounded),
  outerwear('Outerwear', Icons.ac_unit_rounded),
  tops('Tops', Icons.dry_cleaning_rounded),
  bottoms('Bottoms', Icons.straighten_rounded),
  other('Other', Icons.category_rounded);

  const WardrobeCategory(this.label, this.icon);
  final String label;
  final IconData icon;

  static final _eastern = RegExp(
      r'\b(kurtas?|kurtis?|kameez|shalwar|salwar|lawn|unstitched|lehe?ngas?|sherwanis?|waistcoats?|dupattas?|'
      r'frocks?|anarkalis?|ghararas?|shararas?|khaddar|pret|eastern|ethnic|[23] ?-?(pc|piece))\b');
  static final _dresses = RegExp(r'\b(dress(es)?|jump ?suits?|gowns?|maxis?)\b');
  static final _outerwear = RegExp(
      r'\b(jackets?|coats?|hoodies?|sweat ?shirts?|sweaters?|cardigans?|puffers?|blazers?|outerwear|shrugs?)\b');
  static final _bottoms = RegExp(
      r'\b(jeans?|trousers?|pants?|shorts|skirts?|cargos?|joggers?|chinos?|bottoms?|palazzos?|leggings?|culottes?)\b');
  static final _tops = RegExp(r'\b(tees?|t-?shirts?|shirts?|tops?|polos?|blouses?|tanks?|camis?|tunics?)\b');

  static WardrobeCategory of(ProductRecommendation p) {
    final text = '${p.category ?? ''} ${p.title}'.toLowerCase();
    if (_eastern.hasMatch(text)) return eastern;
    if (_dresses.hasMatch(text)) return dresses;
    if (_outerwear.hasMatch(text)) return outerwear;
    if (_bottoms.hasMatch(text)) return bottoms;
    if (_tops.hasMatch(text)) return tops;
    return other;
  }
}
