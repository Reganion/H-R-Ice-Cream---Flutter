import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/favorite/favorite.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:ice_cream/client/messages/messages.dart';
import 'package:ice_cream/client/order/cart.dart';
import 'package:ice_cream/client/order/menu.dart';
import 'package:ice_cream/client/profile/profile.dart';
import 'package:intl/intl.dart';
import 'order/all.dart'; // Adjust path if needed

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.showOrderFailedBanner = false,
  });

  /// When true (e.g. after QR downpayment cancel), shows a top banner: "Order failed".
  final bool showOrderFailedBanner;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late PageController _pageController;

  /// Order-failed toast: slide down, hold 5s, fade out (see [widget.showOrderFailedBanner]).
  bool _orderFailedBannerVisible = false;
  AnimationController? _orderFailedSlideController;
  AnimationController? _orderFailedFadeController;
  Animation<Offset>? _orderFailedSlideAnimation;
  Timer? _autoSlideTimer;
  Timer? _popularSlideTimer;
  bool _userSwiped = false;
  bool _userSwipedPopular = false;
  bool _programmaticScrollTop = false;
  bool _programmaticScrollPopular = false;

  /// Cached user for profile avatar (refreshed on init and when returning from profile).
  Map<String, dynamic>? _cachedUser;

  /// API data: best sellers (top carousel), popular (Popular section), flavors (Flavors grid).
  List<Map<String, dynamic>>? _bestSellers;
  List<Map<String, dynamic>>? _popular;
  List<Map<String, dynamic>>? _flavors;
  bool _loadingHome = true;
  String? _homeError;

  /// Track current page to avoid reading PageController.page (causes assertion when multiple PageViews).
  int _topImagesCurrentPage = 0;
  int _manualSlideCurrentPage = 0;

  /// Cart total quantity (sum of all item quantities) for badge on cart icon.
  int _cartCount = 0;

  int index = 0;
  bool forward = true;
  bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;
  bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1024;
  bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  final TextEditingController _searchController = TextEditingController();
  String searchText = "";

  /// Flavors to display from API only, filtered by search.
  List<Map<String, dynamic>> get _flavorsForDisplay {
    return (_flavors ?? <Map<String, dynamic>>[])
        .where((item) =>
            (item["name"] as String? ?? "")
                .toLowerCase()
                .contains(searchText.toLowerCase()))
        .map((e) => {
              "title": e["name"] as String? ?? "",
              "imageUrl": _imageUrl((e["mobile_image"] ?? e["image"]) as String?),
              "priceDisplay": _formatPrice(e["price"]),
              "isOutOfStock": _isFlavorOutOfStock(e),
              "availabilityMessage": _flavorUnavailableMessage(e),
            })
        .toList();
  }

  /// Base URL without /api/v1 for image paths.
  static String _imageUrl(String? path) {
    if (path == null || path.isEmpty) return "";
    final base = Auth.apiBaseUrl.replaceAll('/api/v1', '');
    return path.startsWith('http') ? path : '$base/$path';
  }

  /// Item count for top (Best Sellers) carousel from API only.
  int get _topCarouselItemCount => _bestSellers?.length ?? 0;

  /// Item count for Popular carousel from API only.
  int get _popularCarouselItemCount => _popular?.length ?? 0;
  final PageController _manualSlideController = PageController();

  /// Parses Laravel-style `{ "data": [ ... ] }` JSON body into a non-empty list or null.
  List<Map<String, dynamic>>? _decodeApiDataList(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>?;
      final data = map?['data'];
      if (data is! List) return null;
      final list = data
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
          .toList();
      return list.isNotEmpty ? list : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches best-sellers, popular, and flavors in parallel. Each section updates the UI
  /// as soon as its response arrives (not after the slowest endpoint), and one [http.Client]
  /// is reused for connection keep-alive.
  Future<void> _loadHomeData() async {
    final base = Auth.apiBaseUrl;
    if (!mounted) return;
    setState(() {
      _loadingHome = true;
      _homeError = null;
    });

    var pending = 3;
    void markRequestDone() {
      if (!mounted) return;
      pending--;
      if (pending <= 0) {
        setState(() => _loadingHome = false);
      }
    }

    final client = http.Client();
    Future<void> loadBestSellers() async {
      try {
        final res = await client.get(Uri.parse('$base/best-sellers'));
        if (!mounted) return;
        if (res.statusCode == 200) {
          final parsed = _decodeApiDataList(res.body);
          if (mounted) {
            setState(() {
              _bestSellers = parsed;
              if (parsed != null) _loadingHome = false;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _homeError ??= e.toString());
        }
      } finally {
        markRequestDone();
      }
    }

    Future<void> loadPopular() async {
      try {
        final res = await client.get(Uri.parse('$base/popular'));
        if (!mounted) return;
        if (res.statusCode == 200) {
          final parsed = _decodeApiDataList(res.body);
          if (mounted) {
            setState(() {
              _popular = parsed;
              if (parsed != null) _loadingHome = false;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _homeError ??= e.toString());
        }
      } finally {
        markRequestDone();
      }
    }

    Future<void> loadFlavors() async {
      try {
        final res = await client.get(Uri.parse('$base/flavors'));
        if (!mounted) return;
        if (res.statusCode == 200) {
          final parsed = _decodeApiDataList(res.body);
          if (mounted) {
            setState(() {
              _flavors = parsed;
              if (parsed != null) _loadingHome = false;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _homeError ??= e.toString());
        }
      } finally {
        markRequestDone();
      }
    }

    try {
      await Future.wait([
        loadBestSellers(),
        loadPopular(),
        loadFlavors(),
      ]);
    } finally {
      client.close();
    }
  }

  /// Format price from API (number or string) to display string.
  static String _formatPrice(dynamic price) {
    if (price == null) return '₱0';
    if (price is num) return '₱${NumberFormat('#,##0').format(price)}';
    return '₱${price.toString()}';
  }

  Widget _imagePlaceholder({double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF3F3F3),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Color(0xFFB0B0B0),
      ),
    );
  }

  bool? _parseBoolLike(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return null;
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  String _normalizeStatus(dynamic value) {
    return (value?.toString() ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');
  }

  bool _statusLooksOutOfStock(dynamic value) {
    final normalized = _normalizeStatus(value);
    if (normalized.isEmpty) return false;
    return <String>{
      'out',
      'outofstock',
      'unavailable',
      'notavailable',
      'soldout',
      'nostock',
      'inactive',
      'disabled',
    }.contains(normalized);
  }

  bool _statusLooksAvailable(dynamic value) {
    final normalized = _normalizeStatus(value);
    if (normalized.isEmpty) return false;
    return <String>{
      'available',
      'instock',
      'active',
      'enabled',
    }.contains(normalized);
  }

  String _readFlavorType(Map<String, dynamic>? flavor) {
    if (flavor == null) return '';
    final keys = <String>[
      'flavor_type',
      'type',
      'flavorType',
      'category',
      'base_flavor',
      'baseFlavor',
    ];
    for (final key in keys) {
      final value = (flavor[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _readFlavorName(Map<String, dynamic>? flavor) {
    if (flavor == null) return '';
    final keys = <String>['name', 'title', 'display_name', 'displayName'];
    for (final key in keys) {
      final value = (flavor[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  bool _isFlavorDirectlyOutOfStock(Map<String, dynamic>? flavor) {
    if (flavor == null) return false;
    final statusCandidates = <dynamic>[
      flavor['status'],
      flavor['availability_status'],
      flavor['stock_status'],
      flavor['availability'],
    ];
    final isOutOfStockStatus = statusCandidates.any(_statusLooksOutOfStock);

    final outOfStockFlag = _parseBoolLike(flavor['is_out_of_stock']) ??
        _parseBoolLike(flavor['out_of_stock']) ??
        false;

    final availableFlag = _parseBoolLike(flavor['is_available']) ??
        _parseBoolLike(flavor['available']) ??
        _parseBoolLike(flavor['in_stock']);

    final stockRaw = flavor['stock'] ?? flavor['stocks'] ?? flavor['quantity'];
    final stockNum = stockRaw is num
        ? stockRaw.toDouble()
        : double.tryParse((stockRaw ?? '').toString().trim());
    final outByStockCount = stockNum != null && stockNum <= 0;

    final explicitAvailableStatus = statusCandidates.any(_statusLooksAvailable);
    if (explicitAvailableStatus && !isOutOfStockStatus && !outOfStockFlag && !outByStockCount) {
      return false;
    }

    return isOutOfStockStatus ||
        outOfStockFlag ||
        (availableFlag != null && !availableFlag) ||
        outByStockCount;
  }

  String _resolveFlavorType(Map<String, dynamic>? flavor) {
    if (flavor == null) return '';
    final ownType = _readFlavorType(flavor);
    if (ownType.isNotEmpty) return ownType.toLowerCase();

    // Best-seller/popular items sometimes omit `flavor_type`.
    final name = _readFlavorName(flavor).toLowerCase();
    if (name.isEmpty) return '';
    for (final raw in (_flavors ?? <Map<String, dynamic>>[])) {
      final candidateName = _readFlavorName(raw).toLowerCase();
      if (candidateName == name) {
        final candidateType = _readFlavorType(raw);
        if (candidateType.isNotEmpty) return candidateType.toLowerCase();
      }
    }
    return '';
  }

  bool _isFlavorOutByTypeGroup(Map<String, dynamic>? flavor) {
    final type = _resolveFlavorType(flavor);
    if (type.isEmpty) return false;
    final source = _flavors ?? <Map<String, dynamic>>[];
    if (source.isEmpty) return false;

    for (final row in source) {
      final rowType = _resolveFlavorType(row);
      if (rowType != type) continue;
      if (_isFlavorDirectlyOutOfStock(row)) {
        return true;
      }
    }
    return false;
  }

  bool _isFlavorOutOfStock(Map<String, dynamic>? flavor) {
    return _isFlavorDirectlyOutOfStock(flavor) || _isFlavorOutByTypeGroup(flavor);
  }

  String _flavorAvailabilityLabel(Map<String, dynamic>? flavor) {
    return _isFlavorOutOfStock(flavor) ? 'Out of Stock' : 'Available';
  }

  String _flavorUnavailableMessage(Map<String, dynamic>? flavor) {
    final apiMessage = (flavor?['availability_message'] as String?)?.trim() ?? '';
    if (apiMessage.isNotEmpty) return apiMessage;
    return 'Sorry, the flavor is not available.';
  }

  void _showFlavorUnavailableMessage(Map<String, dynamic>? flavor) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Not Available'),
          content: Text(_flavorUnavailableMessage(flavor)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOutOfStockOverlay({double borderRadius = 9}) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          alignment: Alignment.center,
          child: const Text(
            'Out of Stock',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvailabilityBadge({
    required bool isOutOfStock,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOutOfStock ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Fetches cart count (sum of quantities) from API for the cart icon badge.
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_onTopImagesPageChanged);
    _manualSlideController.addListener(_onManualSlidePageChanged);
    _loadCachedUser();
    _loadHomeData();
    _fetchCartCount();

    if (widget.showOrderFailedBanner) {
      _orderFailedBannerVisible = true;
      _orderFailedSlideController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 420),
      );
      _orderFailedFadeController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 480),
      );
      _orderFailedSlideAnimation = Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _orderFailedSlideController!,
        curve: Curves.easeOutCubic,
      ));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _orderFailedSlideController!.forward().then((_) {
          if (!mounted) return;
          Future<void>.delayed(const Duration(seconds: 5), () {
            if (!mounted) return;
            _orderFailedFadeController!.forward().then((_) {
              if (mounted) {
                setState(() {
                  _orderFailedBannerVisible = false;
                });
              }
            });
          });
        });
      });
    }

    // Advance topImages to next every 5 seconds
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_userSwiped) return;
      if (!_pageController.hasClients) return;

      final count = _topCarouselItemCount;
      if (count == 0) return;
      int next = _topImagesCurrentPage + 1;
      if (next >= count) next = 0;

      _programmaticScrollTop = true;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _programmaticScrollTop = false;
      });
    });

    // Advance Popular carousel every 8 seconds
    _popularSlideTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      if (_userSwipedPopular) return;
      if (!_manualSlideController.hasClients) return;

      final count = _popularCarouselItemCount;
      if (count == 0) return;
      int next = _manualSlideCurrentPage + 1;
      if (next >= count) next = 0;

      _programmaticScrollPopular = true;
      _manualSlideController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _programmaticScrollPopular = false;
      });
    });

  }

  /// Load avatar: show cached first, then fetch profile from API after login.
  Future<void> _loadCachedUser() async {
    final results = await Future.wait<Object?>([
      Auth.getCachedCustomer(),
      Auth.getApiToken(),
    ]);
    if (!mounted) return;
    final cached = results[0] as Map<String, dynamic>?;
    final token = results[1] as String?;
    setState(() => _cachedUser = cached);
    if (token == null || token.isEmpty) return;
    // Google Firebase ID tokens are JWTs (contain dots) and are not valid for
    // the Laravel /account session endpoint. Keep cached session data in that case.
    if (token.contains('.')) return;
    try {
      final account = await Auth().fetchAccount();
      if (mounted) setState(() => _cachedUser = account);
    } catch (_) {
      // Keep cached avatar if fetch fails (e.g. offline)
    }
  }

  Widget _profileAvatarWidget() {
    final imageUrl = _cachedUser?['image_url'] as String?;
    final imagePath = _cachedUser?['image'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 21,
        backgroundImage: NetworkImage(imageUrl),
      );
    }
    if (imagePath != null && imagePath.isNotEmpty) {
      final baseUrl = Auth.apiBaseUrl.replaceAll('/api/v1', '');
      return CircleAvatar(
        radius: 21,
        backgroundImage: NetworkImage('$baseUrl/$imagePath'),
      );
    }
    return const CircleAvatar(
      radius: 21,
      backgroundImage: AssetImage("lib/client/profile/images/prof.png"),
    );
  }

  void _onTopImagesPageChanged() {
    if (!_pageController.hasClients || !mounted) return;
    final pos = _pageController.position;
    final count = _topCarouselItemCount;
    final page = count > 0 ? (pos.pixels / pos.viewportDimension).round().clamp(0, count - 1) : 0;
    if (_topImagesCurrentPage != page) {
      setState(() => _topImagesCurrentPage = page);
    }
  }

  void _onManualSlidePageChanged() {
    if (!_manualSlideController.hasClients || !mounted) return;
    final pos = _manualSlideController.position;
    final count = _popularCarouselItemCount;
    final page = count > 0 ? (pos.pixels / pos.viewportDimension).round().clamp(0, count - 1) : 0;
    if (_manualSlideCurrentPage != page) {
      setState(() => _manualSlideCurrentPage = page);
    }
  }

  void _stopAutoSlide() {
    _userSwiped = true;
    _autoSlideTimer?.cancel();
  }

  void _stopPopularAutoSlide() {
    _userSwipedPopular = true;
    _popularSlideTimer?.cancel();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _popularSlideTimer?.cancel();
    _pageController.removeListener(_onTopImagesPageChanged);
    _manualSlideController.removeListener(_onManualSlidePageChanged);
    _pageController.dispose();
    _manualSlideController.dispose();
    _orderFailedSlideController?.dispose();
    _orderFailedFadeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      bottomNavigationBar: _bottomNavBar(context),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              const SizedBox(height: 10),

              // PROFILE + CART
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Profile with onPressed (onTap) — refresh avatar when returning
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfilePage(
                            key: ValueKey(DateTime.now().millisecondsSinceEpoch),
                          ),
                        ),
                      ).then((_) {
                        if (mounted) _loadCachedUser();
                      });
                    },
                    child: _profileAvatarWidget(),
                  ),

                  // Shopping cart with badge (cart count)
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CartPage(),
                        ),
                      ).then((_) => _fetchCartCount());
                    },
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
                      child: Container(
                        height: 43,
                        width: 43,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF2F2F2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shopping_cart,
                          color: Color(0xFFE3001B),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // SEARCH BAR
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                height: 48,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Color(0xFFD9D9D9), width: 1),
                ),
                child: Row(
                  children: [
                    Transform.translate(
                      offset: const Offset(-5, 0),
                      child: const Icon(
                        Icons.search,
                        color: Color(0xFFAFAFAF),
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 3),

                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        cursorColor: Colors.black,
                        cursorHeight: 18,
                        onChanged: (value) {
                          setState(() => searchText = value);
                        },
                        style: const TextStyle(
                          fontSize: 14.18,
                          color: Color(0xFF848484),
                        ),
                        decoration: const InputDecoration(
                          hintText: "Search here...",
                          hintStyle: TextStyle(
                            color: Color(0xFF848484),
                            fontSize: 14.18,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
                  ],
                ),
              ),

              // CONTENT
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: false,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const SizedBox(height: 12),
                    if (_loadingHome)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                    if (_homeError != null && _homeError!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Text(
                          'Could not load: ${_homeError ?? ""}',
                          style: const TextStyle(fontSize: 12, color: Colors.red),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    // Best Sellers (top carousel)
                    if (_topCarouselItemCount > 0) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              "Best Sellers",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1C1B1F),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // SLIDER (RESPONSIVE)
                    LayoutBuilder(
                        builder: (context, constraints) {
                          double width =
                              constraints.maxWidth; // full available width
                          double height = width * 0.42; // responsive height
                          if (height < 170) height = 160; // minimum height
                          if (height > 300)
                            height = 300; // max height for desktop

                          final int currentPage = _topImagesCurrentPage;
                          final useBestSellers = _bestSellers?.isNotEmpty == true;
                          final count = _topCarouselItemCount;

                          return GestureDetector(
                            onTap: () {
                              if (count == 0) return;
                              final flavor = _bestSellers![currentPage.clamp(0, count - 1)];
                              if (_isFlavorOutOfStock(flavor)) {
                                _showFlavorUnavailableMessage(flavor);
                                return;
                              }
                              final flavorName = flavor["name"] as String? ?? "";
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      MenuPage(initialFlavorName: flavorName),
                                ),
                              );
                            },
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    isMobile(context) ? 14 : 28,
                                  ),
                                  child: SizedBox(
                                    height: height,
                                    width: width,
                                    child:
                                        NotificationListener<
                                          ScrollNotification
                                        >(
                                          onNotification: (notification) {
                                            if (notification
                                                    is ScrollStartNotification &&
                                                !_programmaticScrollTop) {
                                              _stopAutoSlide();
                                            }
                                            return false;
                                          },
                                          child: PageView.builder(
                                            key: const PageStorageKey<String>('top_images_carousel'),
                                            controller: _pageController,
                                            physics:
                                                const BouncingScrollPhysics(),
                                            itemCount: count,
                                            itemBuilder: (context, i) {
                                              if (!useBestSellers) return const SizedBox.shrink();
                                              final imgUrl = _imageUrl((_bestSellers![i]["mobile_image"] ?? _bestSellers![i]["image"]) as String?);
                                              final isOutOfStock = _isFlavorOutOfStock(_bestSellers![i]);
                                              final availabilityLabel = _flavorAvailabilityLabel(_bestSellers![i]);
                                              return Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(14),
                                                  child: Stack(
                                                    children: [
                                                      Positioned.fill(
                                                        child: imgUrl.isEmpty
                                                            ? _imagePlaceholder(width: width)
                                                            : Image.network(
                                                                imgUrl,
                                                                width: width,
                                                                fit: BoxFit.cover,
                                                                errorBuilder: (_, __, ___) => _imagePlaceholder(width: width),
                                                              ),
                                                      ),
                                                      if (isOutOfStock)
                                                        _buildOutOfStockOverlay(borderRadius: 14),
                                                      Positioned(
                                                        top: 10,
                                                        right: 10,
                                                        child: _buildAvailabilityBadge(
                                                          isOutOfStock: isOutOfStock,
                                                          label: availabilityLabel,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                  ),
                                ),
                                // Overlay on image: name left, star + rating right
                                Positioned(
                                  bottom: 12,
                                  left: 15,
                                  right: 15,
                                  child: AnimatedBuilder(
                                    animation: _pageController,
                                    builder: (context, _) {
                                      final page = _topImagesCurrentPage;
                                      final name = useBestSellers && count > 0
                                          ? (_bestSellers![page.clamp(0, count - 1)]["name"] as String? ?? "")
                                          : "";
                                      final price = useBestSellers && count > 0
                                          ? _formatPrice(_bestSellers![page.clamp(0, count - 1)]["price"])
                                          : "₱0";
                                      const rating = "5.0";
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                name,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: isMobile(context)
                                                      ? 18
                                                      : 16,
                                                  fontWeight: FontWeight.w600,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.black
                                                          .withOpacity(0.4),
                                                      offset: const Offset(0, 1),
                                                      blurRadius: 2,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                price,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: isMobile(context)
                                                      ? 13
                                                      : 14,
                                                  fontWeight: FontWeight.w700,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.black
                                                          .withOpacity(0.45),
                                                      offset: const Offset(0, 1),
                                                      blurRadius: 2,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.star,
                                                color: const Color(0xFFFFD700),
                                                size: isMobile(context)
                                                    ? 18
                                                    : 20,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                rating,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: isMobile(context)
                                                      ? 14
                                                      : 16,
                                                  fontWeight: FontWeight.w600,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.black
                                                          .withOpacity(0.4),
                                                      offset: const Offset(0, 1),
                                                      blurRadius: 2,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            "Popular",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1C1B1F),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Manual slideshow below Popular
                    LayoutBuilder(
                      builder: (context, constraints) {
                        double width = constraints.maxWidth;
                        double height = width * 0.42;
                        if (height < 170) height = 165;
                        if (height > 300) height = 270;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              onTap: () {
                                final page = _manualSlideCurrentPage;
                                final count = _popularCarouselItemCount;
                                if (count == 0) return;
                                final flavor = _popular![page.clamp(0, count - 1)];
                                if (_isFlavorOutOfStock(flavor)) {
                                  _showFlavorUnavailableMessage(flavor);
                                  return;
                                }
                                final name = flavor["name"] as String? ?? "";
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MenuPage(
                                      initialDisplayName: name,
                                      initialFlavorName: name,
                                    ),
                                  ),
                                );
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  isMobile(context) ? 9 : 28,
                                ),
                                child: SizedBox(
                                  height: height,
                                  width: width,
                                  child: NotificationListener<ScrollNotification>(
                                    onNotification: (notification) {
                                      if (notification is ScrollStartNotification &&
                                          !_programmaticScrollPopular) {
                                        _stopPopularAutoSlide();
                                      }
                                      return false;
                                    },
                                    child: PageView.builder(
                                      key: const PageStorageKey<String>('manual_slide_carousel'),
                                      controller: _manualSlideController,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: _popularCarouselItemCount,
                                      itemBuilder: (context, i) {
                                        if (_popular == null || _popular!.isEmpty) return const SizedBox.shrink();
                                        final imgUrl = _imageUrl((_popular![i]["mobile_image"] ?? _popular![i]["image"]) as String?);
                                        final isOutOfStock = _isFlavorOutOfStock(_popular![i]);
                                        final availabilityLabel = _flavorAvailabilityLabel(_popular![i]);
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(9),
                                            child: Stack(
                                              children: [
                                                Positioned.fill(
                                                  child: imgUrl.isEmpty
                                                      ? _imagePlaceholder(width: width)
                                                      : Image.network(
                                                          imgUrl,
                                                          width: width,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => _imagePlaceholder(width: width),
                                                        ),
                                                ),
                                                if (isOutOfStock)
                                                  _buildOutOfStockOverlay(borderRadius: 9),
                                                Positioned(
                                                  top: 10,
                                                  right: 10,
                                                  child: _buildAvailabilityBadge(
                                                    isOutOfStock: isOutOfStock,
                                                    label: availabilityLabel,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 8),
                                  AnimatedBuilder(
                              animation: _manualSlideController,
                              builder: (context, _) {
                                final page = _manualSlideCurrentPage;
                                final usePopular = _popular?.isNotEmpty == true;
                                final count = _popularCarouselItemCount;
                                final name = usePopular && count > 0
                                    ? (_popular![page.clamp(0, count - 1)]["name"] as String? ?? "")
                                    : "";
                                final price = usePopular && count > 0
                                    ? _formatPrice(_popular![page.clamp(0, count - 1)]["price"])
                                    : "₱0";
                                return GestureDetector(
                                  onTap: () {
                                    final p = _manualSlideCurrentPage;
                                    final flavor = usePopular && count > 0
                                        ? _popular![p.clamp(0, count - 1)]
                                        : null;
                                    if (_isFlavorOutOfStock(flavor)) {
                                      _showFlavorUnavailableMessage(flavor);
                                      return;
                                    }
                                    final slideName = usePopular && count > 0
                                        ? (_popular![p.clamp(0, count - 1)]["name"] as String? ?? "")
                                        : "";
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => MenuPage(
                                          initialDisplayName: slideName,
                                          initialFlavorName: slideName,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                color: const Color(0xFF1C1B1F),
                                                fontSize: isMobile(context)
                                                    ? 17
                                                    : 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.star,
                                                color: const Color(0xFFFFD700),
                                                size: isMobile(context)
                                                    ? 18
                                                    : 20,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                "5.0",
                                                style: TextStyle(
                                                  color: const Color(0xFF1C1B1F),
                                                  fontSize: isMobile(context)
                                                      ? 14
                                                      : 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        price,
                                        style: const TextStyle(
                                          color: Color(0xFFE3001B),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    // FLAVORS
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          "Flavors",
                          style: TextStyle(
                            color: Color(0xFF1C1B1F),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MenuPage(),
                              ),
                            );
                          },
                          child: const Text(
                            "See all",
                            style: TextStyle(
                              color: Color(0xFFE3001B),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                        builder: (context, constraints) {
                          double width = constraints.maxWidth;

                          bool isMobile = width < 600;
                          int gridCount = width >= 1000
                              ? 4
                              : width >= 800
                              ? 3
                              : width >= 600
                              ? 2
                              : 1;

                          if (isMobile) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _flavorsForDisplay.isEmpty
                                    ? [
                                        const Text(
                                          "No result found",
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ]
                                    : _flavorsForDisplay.map((item) {
                                        final title = item["title"] as String;
                                        final imageUrl = item["imageUrl"] as String?;
                                        final priceStr = item["priceDisplay"] as String?;
                                        final isOutOfStock = item["isOutOfStock"] as bool? ?? false;
                                        final availabilityLabel =
                                            isOutOfStock ? "Out of Stock" : "Available";
                                        final unavailableMessage =
                                            item["availabilityMessage"] as String?;
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: _flavorCard(
                                            title,
                                            "",
                                            imageUrl: imageUrl,
                                            priceDisplay: priceStr,
                                            isOutOfStock: isOutOfStock,
                                            availabilityLabel: availabilityLabel,
                                            width: 149,
                                            onTap: () {
                                              if (isOutOfStock) {
                                                _showFlavorUnavailableMessage({
                                                  'availability_message': unavailableMessage,
                                                });
                                                return;
                                              }
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      MenuPage(
                                                    initialFlavorName: title,
                                                    initialDisplayName: title,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      }).toList(),
                              ),
                            );
                          }

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _flavorsForDisplay.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridCount,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 0.78,
                                ),
                            itemBuilder: (context, index) {
                              final item = _flavorsForDisplay[index];
                              final title = item["title"] as String;
                              final imageUrl = item["imageUrl"] as String?;
                              final priceStr = item["priceDisplay"] as String?;
                              final isOutOfStock = item["isOutOfStock"] as bool? ?? false;
                              final availabilityLabel =
                                  isOutOfStock ? "Out of Stock" : "Available";
                              final unavailableMessage =
                                  item["availabilityMessage"] as String?;
                              return _flavorCard(
                                title,
                                "",
                                imageUrl: imageUrl,
                                priceDisplay: priceStr,
                                isOutOfStock: isOutOfStock,
                                availabilityLabel: availabilityLabel,
                                onTap: () {
                                  if (isOutOfStock) {
                                    _showFlavorUnavailableMessage({
                                      'availability_message': unavailableMessage,
                                    });
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MenuPage(
                                        initialFlavorName: title,
                                        initialDisplayName: title,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
        if (_orderFailedBannerVisible && _orderFailedSlideAnimation != null)
          _buildOrderFailedBanner(),
      ],
    ),
    );
  }

  /// Full-width bar under safe area: slides down, holds 5s, fades out (not floating SnackBar style).
  Widget _buildOrderFailedBanner() {
    final slide = _orderFailedSlideAnimation!;
    final fade = _orderFailedFadeController!;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SlideTransition(
            position: slide,
            child: FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0).animate(
                CurvedAnimation(parent: fade, curve: Curves.easeOutCubic),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 22),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Order failed',
                          style: TextStyle(
                            color: Color(0xFFB71C1C),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flavorCard(String title, String img,
      {String? imageUrl,
      String? priceDisplay,
      bool isOutOfStock = false,
      String availabilityLabel = "Available",
      double width = 142,
      VoidCallback? onTap}) {
    final useNetworkImage = imageUrl != null && imageUrl.isNotEmpty;
    final card = Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                children: [
                  useNetworkImage
                      ? Image.network(
                          imageUrl,
                          height: width * 0.41,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imagePlaceholder(
                            width: double.infinity,
                            height: width * 0.41,
                          ),
                        )
                      : _imagePlaceholder(
                          width: double.infinity,
                          height: width * 0.41,
                        ),
                  if (isOutOfStock) _buildOutOfStockOverlay(borderRadius: 5),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _buildAvailabilityBadge(
                      isOutOfStock: isOutOfStock,
                      label: availabilityLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1B1F),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  availabilityLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isOutOfStock
                        ? const Color(0xFFC62828)
                        : const Color(0xFF2E7D32),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      priceDisplay ?? "₱1,700",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFFE3001B),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Color(0xFFFFD700), size: 15),
                        const SizedBox(width: 4),
                        const Text(
                          "5.0",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: Color(0xFF1C1B1F),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
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
              active: true,
              onTap: () {},
              fillColor: const Color(0xFFE3001B),
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
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FavoritePage()),
                );
              },
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
  final Color? fillColor;

  const _BottomIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = active ? const Color(0xFFE3001B) : const Color(0xFF969696);
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
