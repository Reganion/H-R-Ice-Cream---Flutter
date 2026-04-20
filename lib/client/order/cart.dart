import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/order/menu.dart';
import 'package:ice_cream/client/widgets/app_loading.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class CartPage extends StatefulWidget {
  const CartPage({Key? key}) : super(key: key);

  @override
  _CartPageState createState() => _CartPageState();
}

/// Parses Firestore / API document id (string or int from JSON).
String? _cartLineIdFromApi(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) return raw.isEmpty ? null : raw;
  if (raw is int) return '$raw';
  if (raw is num) return raw.toInt().toString();
  final s = raw.toString();
  return s.isEmpty ? null : s;
}

/// Cart item from API: id, quantity, flavor (name, image, category), gallon (size, addon_price), line_total.
class CartItem {
  /// Cart line document id (Firestore string or legacy int as string).
  final String id;
  int quantity;
  final String name;
  final String image;
  final bool isNetworkImage;
  final String size;
  /// Display category under product name (e.g. "Plain Flavors", "Special Flavors", "Toppings").
  final String category;
  final double lineTotal;
  /// Gallon addon price per unit (from API gallon.addon_price or gallon.price).
  final double gallonAddonPrice;
  bool selected;

  CartItem({
    required this.id,
    required this.quantity,
    required this.name,
    required this.image,
    required this.isNetworkImage,
    required this.size,
    required this.lineTotal,
    this.category = '',
    this.gallonAddonPrice = 0,
    this.selected = false,
  });

  /// Gallon total for this line: addon_price * quantity.
  double get gallonTotal => gallonAddonPrice * quantity;
}

class _CartPageState extends State<CartPage> {
  List<CartItem> items = [];
  bool _loading = true;
  bool _checkingOut = false;
  String? _error;
  double _subtotal = 0;

  static String _imageUrl(String? path) {
    if (path == null || path.isEmpty) return "";
    final base = Auth.apiBaseUrl.replaceAll('/api/v1', '');
    return path.startsWith('http') ? path : '$base/$path';
  }

  static String _normalizeCategory(String? category) {
    if (category == null || category.isEmpty) return 'Plain Flavors';
    final c = category.toLowerCase().trim();
    if (c.contains('special')) return 'Special Flavors';
    if (c.contains('topping')) return 'Toppings';
    return 'Plain Flavors';
  }

  static String _formatPrice(double value) {
    return '₱${NumberFormat('#,##0').format(value)}';
  }

  bool get allSelected => items.isNotEmpty && items.every((e) => e.selected);
  bool get anySelected => items.any((e) => e.selected);
  double get total =>
      items.where((e) => e.selected).fold(0.0, (sum, e) => sum + e.lineTotal);
  /// Display total: API subtotal when all selected, else sum of selected line_totals.
  double get displayTotal => allSelected ? _subtotal : total;

  Future<void> _fetchCart() async {
    final token = await Auth.getToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Please log in to view cart.';
          items = [];
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final base = Auth.apiBaseUrl;
    try {
      final res = await http.get(
        Uri.parse('$base/cart'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = body?['message'] as String? ?? 'Could not load cart.';
          items = [];
        });
        return;
      }
      final data = body?['data'] as Map<String, dynamic>?;
      final rawItems = data?['items'] as List<dynamic>? ?? [];
      final subtotal = (data?['subtotal'] as num?)?.toDouble() ?? 0.0;
      final list = <CartItem>[];
      for (final raw in rawItems) {
        final map = raw as Map<String, dynamic>;
        final flavor = map['flavor'] as Map<String, dynamic>?;
        final gallon = map['gallon'] as Map<String, dynamic>?;
        final id = _cartLineIdFromApi(map['id']);
        final qty = (map['quantity'] as num?)?.toInt() ?? 1;
        final lineTotal = (map['line_total'] as num?)?.toDouble() ?? 0.0;
        if (id == null) continue;
        final name = flavor?['name'] as String? ?? 'Flavor';
        final imagePath = (flavor?['mobile_image'] ?? flavor?['image']) as String?;
        final image = _imageUrl(imagePath);
        final isNetwork = image.isNotEmpty && image.startsWith('http');
        final size = gallon?['size'] as String? ?? '—';
        final catRaw = flavor?['category'] as String?;
        final category = _normalizeCategory(catRaw);
        final addonRaw = gallon?['addon_price'] ?? gallon?['price'];
        final gallonAddon = addonRaw is num
            ? addonRaw.toDouble()
            : (double.tryParse(addonRaw?.toString() ?? '0') ?? 0);
        list.add(CartItem(
          id: id,
          quantity: qty,
          name: name,
          image: image.isEmpty ? 'lib/client/order/images/sb.png' : image,
          isNetworkImage: isNetwork,
          size: size,
          category: category,
          lineTotal: lineTotal,
          gallonAddonPrice: gallonAddon,
          selected: false,
        ));
      }
      setState(() {
        items = list;
        _subtotal = subtotal;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load cart. Check your connection.';
          items = [];
        });
      }
    }
  }

  void toggleSelectAll(bool value) {
    setState(() {
      for (var item in items) {
        item.selected = value;
      }
    });
  }

  static const int _maxQty = 5;

  Future<void> _updateQuantity(int index, int newQty) async {
    final item = items[index];
    if (newQty < 1 || newQty > _maxQty) return;
    final token = await Auth.getToken();
    if (token == null || token.isEmpty) return;
    final base = Auth.apiBaseUrl;
    try {
      final res = await http.put(
        Uri.parse('$base/cart/${item.id}'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'quantity': newQty}),
      );
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _fetchCart();
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body?['message'] as String? ?? 'Could not update quantity.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update quantity.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void incrementQty(int index) {
    final item = items[index];
    if (item.quantity >= _maxQty) return;
    _updateQuantity(index, item.quantity + 1);
  }

  void decrementQty(int index) {
    final item = items[index];
    if (item.quantity <= 1) return;
    _updateQuantity(index, item.quantity - 1);
  }

  Future<void> removeItem(int index) async {
    final item = items[index];
    final token = await Auth.getToken();
    if (token == null || token.isEmpty) return;
    final base = Auth.apiBaseUrl;
    try {
      final res = await http.delete(
        Uri.parse('$base/cart/${item.id}'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _fetchCart();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove item.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchCart();
  }

  Future<void> _deleteSelectedItems() async {
    final selectedItems = items.where((e) => e.selected).toList();
    if (selectedItems.isEmpty) return;

    final token = await Auth.getToken();
    if (token == null || token.isEmpty) return;

    final base = Auth.apiBaseUrl;

    try {
      await Future.wait(
        selectedItems.map(
          (item) => http.delete(
            Uri.parse('$base/cart/${item.id}'),
            headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
          ),
        ),
      );
      if (mounted) await _fetchCart();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete selected items.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showDeleteSelectedModal(BuildContext context) {
    final selectedCount = items.where((e) => e.selected).length;
    if (selectedCount == 0) return;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Red trash icon at top center
              Icon(
                Symbols.delete,
                size: 45,
                color: const Color(0xFFE3001B),
                fill: 1,
                weight: 400,
                grade: 0,
                opticalSize: 48,
              ),
              const SizedBox(height: 10),
              const Text(
                "Delete selected",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1B1F),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Are you sure you want to delete $selectedCount selected item${selectedCount == 1 ? '' : 's'}?",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.50,
                  color: Color(0xFF747474),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(11.45),
                          border: Border.all(
                            color: const Color(0xFF969696),
                            width: 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          "No, cancel",
                          style: TextStyle(
                            fontSize: 14.36,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF434343),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _deleteSelectedItems();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3001B),
                          borderRadius: BorderRadius.circular(11.45),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          "Yes, I'm sure",
                          style: TextStyle(
                            fontSize: 14.36,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: (_loading || _error != null || items.isNotEmpty)
          ? AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              centerTitle: true,
              leadingWidth: 56,
              leading: Transform.translate(
                offset: const Offset(15, 0),
                child: Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 43,
                      height: 43,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2F2F2),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              title: Container(
                height: 43,
                width: 140,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  "My Cart",
                  style: TextStyle(fontWeight: FontWeight.w400, fontSize: 15.69),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Center(
                    child: GestureDetector(
                      onTap: anySelected ? () => _showDeleteSelectedModal(context) : null,
                      child: Icon(
                        Symbols.delete,
                        size: 22,
                        color: anySelected
                            ? const Color(0xFF171717)
                            : const Color(0xFFA8A8A8),
                        fill: 0,
                        weight: 400,
                        grade: 0,
                        opticalSize: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ) : null,

      body: _loading
          ? const AppLoadingCenter()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF505050)),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _fetchCart,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : items.isEmpty
                  ? _buildEmptyCartBody()
                  : Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Check circle outside the box, on the left, vertically centered
                    SizedBox(
                      height: 97,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              item.selected = !item.selected;
                            });
                          },
                          child: item.selected
                              ? Container(
                                  width: 15,
                                  height: 15,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE3001B),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 15,
                                  height: 15,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF434343),
                                      width: 1,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            item.selected = !item.selected;
                          });
                        },
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              color: Colors.black.withOpacity(0.05),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Transform.translate(
                                  offset: const Offset(2, 2),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: item.isNetworkImage
                                        ? Image.network(
                                            item.image,
                                            width: 65,
                                            height: 65,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Image.asset(
                                              'lib/client/order/images/sb.png',
                                              width: 65,
                                              height: 65,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : Image.asset(
                                            item.image,
                                            width: 65,
                                            height: 65,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.size,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w400,
                                    fontSize: 13,
                                    color: Color(0xFF505050),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatPrice(item.lineTotal),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Move qty buttons to top-right corner
                      Positioned(
                        bottom: 0, // adjust vertical position
                        right: 3, // adjust horizontal position
                        child: Row(
                          children: [
                            _qtyButton(Icons.remove, () => decrementQty(index)),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                item.quantity.toString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _qtyButton(Icons.add, () => incrementQty(index)),
                          ],
                        ),
                      ),

                      // Delete icon at top-right corner
                      Positioned(
                        top: 0,
                        right: 5,
                        child: GestureDetector(
                          onTap: () => removeItem(index),
                          child: Icon(
                            Symbols.delete,
                            size: 16,
                            color: Color(0xFFE3001B),
                            fill: 1,
                            weight: 700,
                            grade: 200,
                            opticalSize: 48,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                    ),
                    ),
                  ],
                );
              },
            ),
          ),
          // FOOTER
          Padding(
            padding: const EdgeInsets.only(
    left: 20,   // horizontal padding
    right: 20,  // horizontal padding
    bottom: 10, // vertical padding only at bottom
  ),// horizontal margin

            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ), // horizontal margin
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    color: Colors.black.withOpacity(0.05),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // --- CUSTOM CIRCLE (Select All) ---
                  GestureDetector(
                    onTap: () => toggleSelectAll(!allSelected),
                    child: allSelected
                        ? Container(
                            width: 15,
                            height: 15,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE3001B),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          )
                        : Container(
                            width: 15,
                            height: 15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF434343),
                                width: 1,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "Select All",
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF434343),
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const Spacer(),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          right: 38,
                        ), // move "Total" slightly left
                        child: const Text(
                          "Total",
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF767676),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        _formatPrice(displayTotal),
                        style: const TextStyle(
                          fontSize: 16.54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 23),
                  ElevatedButton(
                    onPressed: (items.where((e) => e.selected).isEmpty || _checkingOut)
                        ? null
                        : () {
                            final selected = items.where((e) => e.selected).toList();
                            setState(() => _checkingOut = true);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ConfirmOrderPage(
                                  cartItems: selected,
                                  cartSubtotal: displayTotal,
                                ),
                              ),
                            ).then((_) {
                              if (mounted) setState(() => _checkingOut = false);
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFE3001B),
                      disabledBackgroundColor: const Color(0xFFE3001B).withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 45),
                    ),
                    child: _checkingOut
                        ? const AppLoadingOnBrand(size: 22)
                        : Text(
                            items.where((e) => e.selected).isEmpty
                                ? "Checkout"
                                : "Checkout (${items.where((e) => e.selected).length})",
                            style: const TextStyle(
                              fontSize: 17,
                              color: Colors.white,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Arrow back + My Cart design applied to empty cart body (same as app bar).
  Widget _buildEmptyCartBody() {
    return Column(
      children: [
        // Same design as app bar: arrow_back (left), My Cart (center)
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // My Cart pill (center)
                Center(
                  child: Container(
                    height: 43,
                    width: 140,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      "My Cart",
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 15.69,
                      ),
                    ),
                  ),
                ),
                // Arrow back (left, same position)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 22),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 43,
                        height: 43,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF2F2F2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.arrow_back,
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    "lib/client/order/images/no_cart.png",
                    width: 250,
                    height: 250,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "You have no cart today!",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFE9E9E9), // background color
        ),
        child: Icon(icon, size: 11),
      ),
    );
  }
}
