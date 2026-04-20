import 'package:ice_cream/auth.dart';

/// Order item from API (order history list / order detail).
///
/// This model is used by both `OrderHistoryPage` and `DeliveryTrackerPage`.
class OrderRecord {
  /// Firestore document id (often non-numeric).
  final String id;
  final String transactionId;
  final String productName;
  final String productType;
  final String gallonSize;
  final String? productImage;
  final String productImageUrl;
  final String? deliveryDate;
  final String? deliveryTime;
  final String? deliveryAddress;
  final double amount;
  final String amountFormatted;
  final int quantity;
  final String? paymentMethod;
  final String status;
  final String? createdAtFormatted;

  const OrderRecord({
    required this.id,
    required this.transactionId,
    required this.productName,
    required this.productType,
    required this.gallonSize,
    this.productImage,
    required this.productImageUrl,
    this.deliveryDate,
    this.deliveryTime,
    this.deliveryAddress,
    required this.amount,
    required this.amountFormatted,
    required this.quantity,
    this.paymentMethod,
    required this.status,
    this.createdAtFormatted,
  });

  static OrderRecord fromJson(Map<String, dynamic> json) {
    final imagePath = json['product_image'] as String? ?? 'img/default-product.png';
    final url = json['product_image_url'] as String?;
    final base = Auth.apiBaseUrl.replaceAll('/api/v1', '');
    final imageUrl = url ?? (imagePath.startsWith('http') ? imagePath : '$base/$imagePath');

    // Some backends may not return these “formatted” fields; provide safe defaults.
    final amount = (json['amount'] as num?)?.toDouble() ?? 0;
    final formatted = json['amount_formatted'] as String?;

    return OrderRecord(
      id: json['id']?.toString().trim() ?? '',
      transactionId: json['transaction_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? 'Product',
      productType: json['product_type'] as String? ?? '',
      gallonSize: json['gallon_size'] as String? ?? '—',
      productImage: json['product_image'] as String?,
      productImageUrl: imageUrl,
      deliveryDate: json['delivery_date'] as String?,
      deliveryTime: json['delivery_time'] as String?,
      deliveryAddress: json['delivery_address'] as String?,
      amount: amount,
      amountFormatted: formatted ?? '₱${amount.toStringAsFixed(2)}',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      paymentMethod: json['payment_method'] as String?,
      status: (json['status'] as String? ?? '').toLowerCase(),
      createdAtFormatted: json['created_at_formatted'] as String? ?? json['created_at'] as String?,
    );
  }

  bool get isCompleted => status == 'delivered' || status == 'walk_in';
  bool get isProcessing => status == 'pending' || status == 'assigned';
  bool get isCancelled => status == 'cancelled';

  /// Copy with updated fields (used when merging real-time status from Firebase).
  OrderRecord copyWith({
    String? id,
    String? transactionId,
    String? productName,
    String? productType,
    String? gallonSize,
    String? productImage,
    String? productImageUrl,
    String? deliveryDate,
    String? deliveryTime,
    String? deliveryAddress,
    double? amount,
    String? amountFormatted,
    int? quantity,
    String? paymentMethod,
    String? status,
    String? createdAtFormatted,
  }) {
    return OrderRecord(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      productName: productName ?? this.productName,
      productType: productType ?? this.productType,
      gallonSize: gallonSize ?? this.gallonSize,
      productImage: productImage ?? this.productImage,
      productImageUrl: productImageUrl ?? this.productImageUrl,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      amount: amount ?? this.amount,
      amountFormatted: amountFormatted ?? this.amountFormatted,
      quantity: quantity ?? this.quantity,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: (status ?? this.status).toLowerCase(),
      createdAtFormatted: createdAtFormatted ?? this.createdAtFormatted,
    );
  }
}

