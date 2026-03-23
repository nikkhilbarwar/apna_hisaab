import 'item_model.dart';

class CartItem {
  final ItemModel item;
  double quantity;
  double price;
  String variant; 
  String unit;
  double extraPieces; 
  double extraPrice; 

  CartItem({
    required this.item,
    required this.quantity,
    required this.price,
    required this.variant,
    required this.unit,
    this.extraPieces = 0,
    this.extraPrice = 0,
  });
}
