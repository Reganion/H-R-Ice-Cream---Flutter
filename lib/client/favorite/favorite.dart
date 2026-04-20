import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/home_page.dart';
import 'package:ice_cream/client/messages/messages.dart';
import 'package:ice_cream/client/order/all.dart';
import 'package:ice_cream/client/order/cart.dart';
import 'package:ice_cream/client/order/menu.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  List<Map<String, dynamic>>? _favorites;
  bool _loading = true;
  String? _error;
  int _cartCount = 0;

  static const _cardColors = [
    Color(0xFFFFE0E6),
    Color(0xFFEDE1F5),
    Color(0xFFFFF2D7),
    Color(0xFFE4F7E9),
    Color(0xFFFFF3DD),
    Color(0xFFEDE1F5),
  ];

  static String _imageUrl(String? path) {
    if (path == null || path.isEmpty) return "";
    final base = Auth.apiBaseUrl.replaceAll('/api/v1', '');
    return path.startsWith('http') ? path : '$base/$path';
  }

  static String _formatPrice(dynamic price) {
    if (price == null) return '₱0';
    final num? n = price is num ? price : double.tryParse(price.toString());
    if (n == null) return '₱0';
    return '₱${NumberFormat('#,##0').format(n)}';
  }

  Future<void> _fetchCartCount() async {
    final token = await Auth.getApiToken();
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _cartCount = 0);
      return;
    }
    final base = Auth.apiBaseUrl;
    try {
      final res = await http.get(
        Uri.parse('$base/cart'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => _cartCount = 0);
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      final data = body?['data'] as Map<String, dynamic>?;
      final rawItems = data?['items'] as List<dynamic>? ?? [];
      int total = 0;
      for (final raw in rawItems) {
        final map = raw as Map<String, dynamic>;
        total += (map['quantity'] as num?)?.toInt() ?? 0;
      }
      setState(() => _cartCount = total);
    } catch (_) {
      if (mounted) setState(() => _cartCount = 0);
    }
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = await Auth.getApiToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Please log in to see your favorites.';
          _favorites = null;
        });
      }
      return;
    }
    final base = Auth.apiBaseUrl;
    try {
      final res = await http.get(
        Uri.parse('$base/favorites'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (res.statusCode == 401) {
        setState(() {
          _loading = false;
          _error = 'Session expired. Please log in again.';
          _favorites = null;
        });
        return;
      }
      if (res.statusCode != 200 || data?['success'] != true) {
        setState(() {
          _loading = false;
          _error = 'Could not load favorites.';
          _favorites = null;
        });
        return;
      }
      final raw = data!['data'];
      List<Map<String, dynamic>> list = [];
      if (raw is List) {
        for (int i = 0; i < raw.length; i++) {
          final e = raw[i];
          if (e is! Map) continue;
          final map = Map<String, dynamic>.from(e);
          // Support both flat flavor and nested flavor (e.g. pivot with flavor)
          final flavor = map['flavor'] is Map
              ? Map<String, dynamic>.from(map['flavor'] as Map<dynamic, dynamic>)
              : map;
          final name = flavor['name'] as String? ?? '';
          final priceRaw = flavor['price'];
          final price = priceRaw is num
              ? priceRaw.toDouble()
              : (double.tryParse(priceRaw?.toString() ?? '0') ?? 0.0);
          final imagePath = (flavor['mobile_image'] ?? flavor['image']) as String?;
          final image = _imageUrl(imagePath);
          list.add({
            'id': flavor['id']?.toString(),
            'name': name,
            'price': price,
            'priceDisplay': _formatPrice(price),
            'image': image.isEmpty ? 'lib/client/favorite/images/sb.png' : image,
            'isNetworkImage': image.isNotEmpty && image.startsWith('http'),
            'color': _cardColors[i % _cardColors.length],
          });
        }
      }
      setState(() {
        _loading = false;
        _error = null;
        _favorites = list;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load favorites.';
          _favorites = null;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _fetchCartCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Container(
          margin: const EdgeInsets.only(left: 15),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 22),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        title: Container(
          height: 45,
          width: 155,
          alignment: Alignment.center, // <-- this centers the text
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            color: Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Text(
            "My Favorite List",
            style: TextStyle(fontWeight: FontWeight.w400, fontSize: 15.69),
            textAlign: TextAlign.center, // optional but recommended
          ),
        ),

        actions: [
          Container(
            margin: const EdgeInsets.only(right: 15),
            height: 46.82,
            width: 46.82,
            decoration: const BoxDecoration(
              color: Color(0xFFF2F2F2),
              shape: BoxShape.circle,
            ),
            child: Badge(
              isLabelVisible: _cartCount > 0,
              label: Text(
                _cartCount >= 99 ? '99+' : '$_cartCount',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              backgroundColor: const Color(0xFFE3001B),
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CartPage()),
                  ).then((_) => _fetchCartCount());
                },
                icon: const Icon(
                  Icons.shopping_cart,
                  size: 22,
                  color: Color(0xFFE3001B),
                  fill: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),

      body: _buildBody(),

      bottomNavigationBar: _bottomNavBar(context),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          height: 32,
          width: 32,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF505050)),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadFavorites,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final items = _favorites ?? [];
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No favorites yet',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the heart on a flavor to add it here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFavorites,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        child: GridView.builder(
          itemCount: items.length,
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 187,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          final image = item['image'] as String? ?? 'lib/client/favorite/images/sb.png';
          final isNetwork = item['isNetworkImage'] == true;
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MenuPage(initialFlavorName: item['name'] as String? ?? ''),
                ),
              );
            },
            child: Container(
              margin: EdgeInsets.only(
                bottom: index >= items.length - 2 ? 6 : 0,
              ),
              decoration: BoxDecoration(
                color: item['color'] as Color? ?? _cardColors[index % _cardColors.length],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 114.36,
                        width: double.infinity,
                        child: isNetwork && image.startsWith('http')
                            ? Image.network(
                                image,
                                height: 114.36,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Image.asset(
                                  'lib/client/favorite/images/sb.png',
                                  height: 114.36,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                image,
                                height: 114.36,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 10, right: 10),
                    child: Text(
                      item['name'] as String? ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 10, right: 10, top: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item['priceDisplay'] as String? ?? _formatPrice(item['price']),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Icon(Icons.favorite, color: Colors.red, size: 17),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _bottomNavBar(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      elevation: 0,
      child: SizedBox(
        height: 65,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BottomIcon(
              icon: Symbols.home,
              label: "Home",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage()),
                );
              },
            ),
            _BottomIcon(
              icon: Symbols.local_mall,
              label: "Order",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrderHistoryPage()),
                );
              },
            ),
            _BottomIcon(
              icon: Symbols.favorite,
              label: "Favorite",
              active: true,
              onTap: () {},
              fillColor: const Color(0xFFE3001B),
            ),
            _BottomIcon(
              icon: Symbols.chat,
              label: "Messages",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MessagesPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? fillColor; // New parameter for custom fill color

  const _BottomIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.fillColor, // Allow fillColor to be passed
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = active ? Color(0xFFE3001B) : const Color(0xFF969696);
    final double fillValue = (active && fillColor != null) ? 1 : 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 21,
              color: fillColor != null && active ? fillColor : iconColor,
              fill: fillValue,
              weight: 100,
              grade: 200,
              opticalSize: 24,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: iconColor,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

