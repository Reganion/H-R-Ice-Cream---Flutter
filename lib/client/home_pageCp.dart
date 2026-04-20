
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:ice_cream/client/favorite/favorite.dart';
// import 'package:ice_cream/client/messages/messages.dart';
// import 'package:ice_cream/client/order/cart.dart';
// import 'package:ice_cream/client/order/menu.dart';
// import 'package:ice_cream/client/profile/profile.dart';
// import 'order/all.dart'; // Adjust path if needed

// class HomePage extends StatefulWidget {
//   const HomePage({super.key});

//   @override
//   State<HomePage> createState() => _HomePageState();
// }

// class _HomePageState extends State<HomePage> {
//   late PageController _pageController;
//   Timer? _autoSlideTimer;
//   bool _userSwiped = false;

//   int index = 0;
//   bool forward = true;

//   final TextEditingController _searchController = TextEditingController();
//   String searchText = "";

//   final List<Map<String, String>> flavors = [
//     {"title": "Cookies & Cream", "img": "lib/client/images/home_page/CC.png"},
//     {"title": "Strawberry", "img": "lib/client/images/home_page/SB.png"},
//     {"title": "Vanilla", "img": "lib/client/images/home_page/SB.png"},
//     {"title": "Chocolate", "img": "lib/client/images/home_page/CC.png"},
//   ];

//   final List<Map<String, String>> recommends = [
//     {"title": "Matcha Ice Cream", "img": "lib/client/images/home_page/MIC.png"},
//     {"title": "Rum Raisin", "img": "lib/client/images/home_page/RR.png"},
//     {"title": "Chocolate", "img": "lib/client/images/home_page/MIC.png"},
//   ];

//   List<Map<String, String>> get filteredFlavors {
//     return flavors
//         .where(
//           (item) =>
//               item["title"]!.toLowerCase().contains(searchText.toLowerCase()),
//         )
//         .toList();
//   }

//   List<Map<String, String>> get filteredRecommends {
//     return recommends
//         .where(
//           (item) =>
//               item["title"]!.toLowerCase().contains(searchText.toLowerCase()),
//         )
//         .toList();
//   }

//   final List<String> topImages = [
//     "lib/client/images/home_page/TOP1.png",
//     "lib/client/images/home_page/TOP2.png",
//     "lib/client/images/home_page/TOP3.png",
//   ];

//   @override
//   void initState() {
//     super.initState();

//     Timer.periodic(const Duration(seconds: 2), (timer) {
//       if (!mounted) return;

//       setState(() {
//         if (forward) {
//           index++;
//           if (index == topImages.length - 1) forward = false;
//         } else {
//           index--;
//           if (index == 0) forward = true;
//         }
//       });

//       _pageController.animateToPage(
//         index,
//         duration: const Duration(milliseconds: 500),
//         curve: Curves.easeInOut,
//       );
//     });

//     _pageController = PageController();

//     _autoSlideTimer = Timer.periodic(const Duration(seconds: 3), (_) {
//       if (!_userSwiped) {
//         if (_pageController.hasClients) {
//           int next = _pageController.page!.round() + 1;
//           if (next == topImages.length) next = 0;

//           _pageController.animateToPage(
//             next,
//             duration: const Duration(milliseconds: 500),
//             curve: Curves.easeInOut,
//           );
//         }
//       }
//     });
//   }

//   void _stopAutoSlide() {
//     _userSwiped = true;
//     _autoSlideTimer?.cancel();
//   }

//   @override
//   void dispose() {
//     _pageController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFFAFAFA),
//       bottomNavigationBar: _bottomNavBar(),
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 20),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const SizedBox(height: 10),

//               // PROFILE + CART
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   // Profile with onPressed (onTap)
//                   GestureDetector(
//                     onTap: () {
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (context) => const ProfilePage(),
//                         ),
//                       );
//                     },
//                     child: const CircleAvatar(
//                       radius: 21,
//                       backgroundImage: AssetImage(
//                         "lib/client/profile/images/prof.png",
//                       ),
//                     ),
//                   ),

//                   // Shopping cart with onPressed (onTap)
//                   GestureDetector(
//                     onTap: () {
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (context) => const CartPage(),
//                         ),
//                       );
//                     },
//                     child: Container(
//                       height: 43,
//                       width: 43,
//                       decoration: const BoxDecoration(
//                         color: Color(0xFFF2F2F2),
//                         shape: BoxShape.circle,
//                       ),
//                       child: const Icon(
//                         Icons.shopping_cart,
//                         color: Color(0xFFE3001B),
//                         size: 22,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),

//               const SizedBox(height: 13),

//               // SEARCH BAR
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 20),
//                 height: 48,
//                 width: double.infinity,
//                 decoration: BoxDecoration(
//                   color: Colors.white,
//                   borderRadius: BorderRadius.circular(26),
//                   border: Border.all(color: Color(0xFFD9D9D9), width: 1),
//                 ),
//                 child: Row(
//                   children: [
//                     Transform.translate(
//                       offset: const Offset(-5, 0),
//                       child: const Icon(
//                         Icons.search,
//                         color: Color(0xFFAFAFAF),
//                         size: 23,
//                       ),
//                     ),
//                     const SizedBox(width: 3),

//                     Expanded(
//                       child: TextField(
//                         controller: _searchController,
//                         cursorColor: Colors.black,
//                         cursorHeight: 18,
//                         onChanged: (value) {
//                           setState(() => searchText = value);
//                         },
//                         style: const TextStyle(
//                           fontSize: 14.18,
//                           color: Color(0xFF848484),
//                         ),
//                         decoration: const InputDecoration(
//                           hintText: "Search here...",
//                           hintStyle: TextStyle(
//                             color: Color(0xFF848484),
//                             fontSize: 14.18,
//                           ),
//                           border: InputBorder.none,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//               const SizedBox(height: 10),

//               // CONTENT
//               Expanded(
//                 child: ListView(
//                   padding: EdgeInsets.zero,
//                   physics:
//                       MediaQuery.of(context).orientation == Orientation.portrait
//                       ? const NeverScrollableScrollPhysics()
//                       : const AlwaysScrollableScrollPhysics(),
//                   children: [
//                     const Text(
//                       "Top Orders",
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.w500,
//                         color: Color(0xFFE3001B),
//                       ),
//                     ),
//                     const SizedBox(height: 8),

//                     // SLIDER
//                     Transform.translate(
//                       offset: const Offset(0, -3),
//                       child: Stack(
//                         children: [
//                           ClipRRect(
//                             borderRadius: BorderRadius.circular(20),
//                             child: SizedBox(
//                               height: 180,
//                               width: 376,
//                               child: NotificationListener<ScrollNotification>(
//                                 onNotification: (notification) {
//                                   if (notification is ScrollStartNotification) {
//                                     _stopAutoSlide();
//                                   }
//                                   return false;
//                                 },
//                                 child: PageView.builder(
//                                   controller: _pageController,
//                                   physics: const BouncingScrollPhysics(),
//                                   itemCount: topImages.length,
//                                   itemBuilder: (context, i) {
//                                     return Image.asset(
//                                       topImages[i],
//                                       fit: BoxFit.cover,
//                                     );
//                                   },
//                                 ),
//                               ),
//                             ),
//                           ),
//                           Positioned(
//                             bottom: 5,
//                             right: 15,
//                             child: ElevatedButton(
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: Colors.white,
//                                 foregroundColor: Color(0xFFE3001B),
//                                 minimumSize: const Size(95, 35),
//                                 padding: EdgeInsets.zero,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(30),
//                                 ),
//                               ),
//                               onPressed: () {},
//                               child: const Text(
//                                 "Order Now",
//                                 style: TextStyle(
//                                   fontSize: 13,
//                                   fontWeight: FontWeight.w500,
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),

//                     // FLAVORS TITLE
//                     Transform.translate(
//                       offset: const Offset(0, -6),
//                       child: Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           const Text(
//                             "Flavors",
//                             style: TextStyle(
//                               fontSize: 18,
//                               fontWeight: FontWeight.w500,
//                               color: Color(0xFF1C1B1F),
//                             ),
//                           ),
//                           Transform.translate(
//                             offset: const Offset(8, 0),
//                             child: TextButton(
//                               onPressed: () {
//                                 Navigator.push(
//                                   context,
//                                   MaterialPageRoute(
//                                     builder: (context) => const MenuPage(),
//                                   ),
//                                 );
//                               },
//                               child: const Text(
//                                 "See All",
//                                 style: TextStyle(
//                                   color: Color(0xFFE3001B),
//                                   fontWeight: FontWeight.w600,
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),

//                     // FLAVORS CARDS (SEARCH FILTERED)
//                     Transform.translate(
//                       offset: const Offset(0, -10),
//                       child: SingleChildScrollView(
//                         scrollDirection: Axis.horizontal,
//                         child: Row(
//                           children: filteredFlavors.isEmpty
//                               ? [
//                                   const Text(
//                                     "No result found",
//                                     style: TextStyle(fontSize: 14),
//                                   ),
//                                 ]
//                               : filteredFlavors.map((item) {
//                                   return Padding(
//                                     padding: const EdgeInsets.only(right: 12),
//                                     child: _flavorCard(
//                                       item["title"]!,
//                                       item["img"]!,
//                                     ),
//                                   );
//                                 }).toList(),
//                         ),
//                       ),
//                     ),

//                     // WE RECOMMEND TITLE
//                     Transform.translate(
//                       offset: const Offset(0, -4),
//                       child: const Text(
//                         "We Recommend",
//                         style: TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.w500,
//                           color: Color(0xFF1C1B1F),
//                         ),
//                       ),
//                     ),

//                     // RECOMMEND CARDS (SEARCH FILTERED)
//                     Transform.translate(
//                       offset: const Offset(0, 2),
//                       child: SingleChildScrollView(
//                         scrollDirection: Axis.horizontal,
//                         child: Row(
//                           children: filteredRecommends.isEmpty
//                               ? [
//                                   const Text(
//                                     "No result found",
//                                     style: TextStyle(fontSize: 14),
//                                   ),
//                                 ]
//                               : filteredRecommends.map((item) {
//                                   return Padding(
//                                     padding: const EdgeInsets.only(right: 12),
//                                     child: _recommendCard(
//                                       item["title"]!,
//                                       item["img"]!,
//                                     ),
//                                   );
//                                 }).toList(),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//               const SizedBox(height: 4),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _flavorCard(String title, String img) {
//     return Container(
//       width: 155,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(18),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.grey.shade100,
//             blurRadius: 5,
//             offset: const Offset(1, 3),
//           ),
//         ],
//       ),
//       padding: const EdgeInsets.all(8),
//       child: Column(
//         children: [
//           ClipRRect(
//             borderRadius: BorderRadius.circular(15),
//             child: Image.asset(
//               img,
//               height: 80,
//               width: double.infinity,
//               fit: BoxFit.cover,
//             ),
//           ),
//           const SizedBox(height: 6),
//           Text(
//             title,
//             style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//           ),
//           const SizedBox(height: 4),
//           const Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(Icons.star, color: Colors.amber, size: 14),
//               Icon(Icons.star, color: Colors.amber, size: 14),
//               Icon(Icons.star, color: Colors.amber, size: 14),
//               Icon(Icons.star, color: Colors.amber, size: 14),
//               Icon(Icons.star_border, size: 14),
//             ],
//           ),
//           const SizedBox(height: 4),
//           const Text(
//             "\$ 100",
//             style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _recommendCard(String title, String img) {
//     return Container(
//       width: 180,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(18),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.grey.shade100,
//             blurRadius: 5,
//             offset: Offset(1, 3),
//           ),
//         ],
//       ),
//       padding: const EdgeInsets.all(8),
//       child: Row(
//         children: [
//           ClipRRect(
//             borderRadius: BorderRadius.circular(10),
//             child: Image.asset(img, height: 51, width: 50, fit: BoxFit.cover),
//           ),
//           const SizedBox(width: 8),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   title,
//                   style: const TextStyle(
//                     fontWeight: FontWeight.w800,
//                     fontSize: 11,
//                   ),
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                 ),
//                 const SizedBox(height: 4),
//                 const Row(
//                   children: [
//                     Icon(Icons.star, color: Colors.amber, size: 10),
//                     Icon(Icons.star, color: Colors.amber, size: 10),
//                     Icon(Icons.star, color: Colors.amber, size: 10),
//                     Icon(Icons.star_half, color: Colors.amber, size: 10),
//                   ],
//                 ),
//                 const SizedBox(height: 4),
//                 const Text(
//                   "\$ 120",
//                   style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _bottomNavBar() {
//     return Card(
//       margin: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
//       color: Colors.white,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
//       elevation: 0,
//       child: SizedBox(
//         height: 65,
//         child: Row(
//           mainAxisAlignment: MainAxisAlignment.spaceAround,
//           children: [
//             _BottomIcon(
//               imagePath: "lib/client/images/home_page/home.png",
//               label: "Home",
//               active: true,
//               onTap: () {},
//             ),
//             _BottomIcon(
//               imagePath: "lib/client/images/home_page/local_mall.png",
//               label: "Order",
//               onTap: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (context) => const OrderHistoryPage(),
//                   ),
//                 );
//               },
//             ),
//             _BottomIcon(
//               imagePath: "lib/client/images/home_page/favorite.png",
//               label: "Favorite",
//               onTap: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(builder: (context) => const FavoritePage()),
//                 );
//               },
//             ),
//             _BottomIcon(
//               imagePath: "lib/client/images/home_page/chat.png",
//               label: "Messages",
//               onTap: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(builder: (context) => const MessagesPage()),
//                 );
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _BottomIcon extends StatelessWidget {
//   final IconData? icon;
//   final String? imagePath;
//   final String label;
//   final bool active;
//   final VoidCallback? onTap;

//   const _BottomIcon({
//     this.icon,
//     this.imagePath,
//     required this.label,
//     this.active = false,
//     this.onTap,

//   });

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           if (imagePath != null)
//             Image.asset(
//               imagePath!,
//               height: 16,
//               width: 18,
//               color: active ? const Color(0xFFE3001B) : const Color(0xFF969696),
//               fit: BoxFit.contain,
//             )
//           else if (icon != null)
//             Icon(
//               icon,
//               color: active ? const Color(0xFFE3001B) : const Color(0xFF969696),
//             ),
//           const SizedBox(height: 4),
//           Text(
//             label,
//             style: TextStyle(
//               fontSize: 11,
//               color: active ? const Color(0xFFE3001B) : const Color(0xFF969696),
//               fontWeight: active ? FontWeight.w700 : FontWeight.normal,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
