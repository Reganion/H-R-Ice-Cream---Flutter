import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:ice_cream/client/order/map_picker_page.dart';
import 'package:ice_cream/client/order/menu.dart';
import 'package:latlong2/latlong.dart';

class ManageAddressPage extends StatefulWidget {
  const ManageAddressPage({super.key, this.fromProfile = false});

  /// When true, back and Save & Continue pop back (e.g. to Address Details) instead of going to Checkout.
  final bool fromProfile;

  @override
  State<ManageAddressPage> createState() => _ManageAddressPageState();
}

class _ManageAddressPageState extends State<ManageAddressPage> {
  int selectedLabelIndex = -1;

  final TextEditingController firstNameController = TextEditingController(
    text: "Alma Fe",
  );
  final TextEditingController lastNameController = TextEditingController(
    text: "Pepania",
  );
  final TextEditingController contactController = TextEditingController(
    text: "9945936764",
  );
  final TextEditingController streetController = TextEditingController(
    text: "Briones st., ACLC College of Mandaue",
  );

  // --------------------- NEW VARIABLES ---------------------
  String selectedProvince = "Cebu";
  String selectedCity = "Mandaue";
  String selectedBarangay = "Maguikay";
  String selectedPostalCode = "";

  final Map<String, List<String>> barangaysByCity = {
    "Mandaue": [
      "Alang-Alang",
      "Bakilid",
      "Banilad",
      "Basak",
      "Cabancalan",
      "Cambaro",
      "Canduman",
      "Centro",
      "Guizo",
      "Ibabao-Estancia",
      "Jagobiao",
      "Labogon",
      "Looc",
      "Maguikay",
      "Mantuyong",
      "Opao",
      "Pagsabungan",
      "Subangdaku",
      "Tabok",
      "Tawason",
      "Tipolo",
      "Umapad",
    ],
    "Lapu-Lapu": [
      "Agus",
      "Babag",
      "Bankal",
      "Basak",
      "Buaya",
      "Canjulao",
      "Gun-ob",
      "Ibo",
      "Looc",
      "Mactan",
      "Maribago",
      "Marigondon",
      "Pajac",
      "Pajo",
      "Poblacion",
      "Punta Engaño",
      "Pusok",
      "Subabasbas",
      "Talima",
      "Tingo",
    ],
  };

  // Auto postal code
  String get postalCode {
    if (selectedPostalCode.isNotEmpty) return selectedPostalCode;
    return selectedCity == "Mandaue" ? "6014" : "6015";
  }

  // --------------------- BUILD UI ---------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 43,
        leading: Transform.translate(
          offset: const Offset(20, 0),
          child: SizedBox(
            child: Material(
              color: const Color(0xFFF2F2F2),
              shape: const CircleBorder(),
              clipBehavior: Clip.hardEdge,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  if (widget.fromProfile) {
                    Navigator.pop(context);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CheckoutPage(),
                      ),
                    );
                  }
                },
                child: const Center(
                  child: Icon(Icons.arrow_back, size: 20, color: Colors.black),
                ),
              ),
            ),
          ),
        ),
        title: Container(
          height: 43,
          width: 160,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Text(
            "Manage Address",
            style: TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: 15.69,
              color: Colors.black,
            ),
          ),
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 10,
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // FIRST + LAST NAME
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label("First Name"),
                        _textField(firstNameController),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label("Last Name"),
                        _textField(lastNameController),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // CONTACT NUMBER
              _label("Contact Number"),
              _textField(
                contactController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
              ),

              const SizedBox(height: 8),

              // PROVINCE + CITY
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label("Province"),
                        _dropdown(
                          selectedProvince,
                          ["Cebu"],
                          (v) => setState(() => selectedProvince = v!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label("City"),
                        _dropdown(selectedCity, ["Mandaue", "Lapu-Lapu"], (v) {
                          setState(() {
                            selectedCity = v!;
                            selectedBarangay = barangaysByCity[v]!.first;
                            selectedPostalCode = selectedCity == "Mandaue" ? "6014" : "6015";
                          });
                        }),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // BARANGAY + POSTAL
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label("Barangay"),
                        _dropdown(
                          selectedBarangay,
                          barangaysByCity[selectedCity]!,
                          (v) => setState(() => selectedBarangay = v!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label("Postal Code"),
                        _disabledField(postalCode),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // STREET
              _label("Street Name, Building, House No."),
              _textField(streetController),

              const SizedBox(height: 8),

              GestureDetector(
                onTap: () async {
                  final result = await Navigator.push<dynamic>(
                    context,
                    MaterialPageRoute(builder: (_) => const MapPickerPage()),
                  );

                  if (!mounted) return;
                  if (result is LatLng) {
                    await _applyPickedLocation(result);
                  }
                },
                child: Container(
                  height: 114,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 18,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E5E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.add, color: Color(0xff949494)),
                          SizedBox(width: 6),
                          Text(
                            "Add Location",
                            style: TextStyle(
                              color: Color(0xff949494),
                              fontSize: 12.55,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              _label("Label as:"),
              const SizedBox(height: 6),

              // LABEL BUTTONS
              Row(
                children: List.generate(3, (index) {
                  final labels = ["Home", "Work", "Other"];
                  final isSelected = selectedLabelIndex == index;

                  return Padding(
                    padding: EdgeInsets.only(right: index != 2 ? 10 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() => selectedLabelIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: isSelected
                              ? const Color(0xFFE3001B)
                              : Colors.white,
                          border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : const Color(0xFFDEDEDE),
                          ),
                        ),
                        child: Text(
                          labels[index],
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF1C1B1F),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 11),

              // SAVE BUTTON
              GestureDetector(
                onTap: () {
                  final normalizedContact = normalizeContactDigits(contactController.text);
                  if (normalizedContact == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Contact number must be 10-11 digits and start with 9 (e.g. 9945936764).',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  // Save only local digits (strip +63 if pasted).
                  if (contactController.text != normalizedContact) {
                    contactController.text = normalizedContact;
                  }
                  if (widget.fromProfile) {
                    Navigator.pop(context);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CheckoutPage()),
                    );
                  }
                },
                child: Container(
                  height: 55,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3001B),
                    borderRadius: BorderRadius.circular(35),
                  ),
                  child: const Center(
                    child: Text(
                      "Save & Continue",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------- HELPERS ----------------------

  Future<void> _applyPickedLocation(LatLng coords) async {
    // Default to Cebu since your UI only supports Cebu -> Mandaue/Lapu-Lapu.
    var nextProvince = "Cebu";
    String? nextCity;
    String? nextBarangay;
    String? nextPostalCode;
    String? nextStreet;

    try {
      final placemarks = await placemarkFromCoordinates(
        coords.latitude,
        coords.longitude,
      );

      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final adminArea = (pm.administrativeArea ?? "").toLowerCase();
        if (adminArea.contains("cebu")) nextProvince = "Cebu";

        nextPostalCode = (pm.postalCode ?? "").trim();
        // City can appear in `locality` or `subAdministrativeArea` depending on platform.
        final rawCity = [pm.locality, pm.subAdministrativeArea, pm.administrativeArea]
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .join(", ");
        nextCity = _mapCityFromRawText(rawCity);

        // Barangay is often found in `subLocality` (may not always match exactly).
        nextBarangay = _matchBarangayFromRawText(pm.subLocality, nextCity);

        // Street is optional, but helps when user doesn't type manually.
        nextStreet = (pm.thoroughfare ?? pm.name ?? "").trim();
      }
    } catch (_) {
      // If reverse geocoding fails, we still guess city from coordinates below.
    }

    // Fallback: guess city by proximity to city centers.
    nextCity ??= _guessCityByDistance(coords);
    final city = nextCity;

    final cityBarangays = barangaysByCity[city] ?? const <String>[];

    // Fallback: pick first barangay if we couldn't match from geocoder.
    nextBarangay ??= cityBarangays.isNotEmpty ? cityBarangays.first : selectedBarangay;

    // Always keep postal code consistent even if geocoder returns null/empty.
    final cityPostal = city == "Mandaue" ? "6014" : "6015";
    nextPostalCode = (nextPostalCode != null && nextPostalCode.isNotEmpty)
        ? nextPostalCode
        : cityPostal;

    // Apply updates.
    if (!mounted) return;
    setState(() {
      selectedProvince = nextProvince;
      selectedCity = city;
      selectedBarangay = nextBarangay ?? selectedBarangay;
      selectedPostalCode = nextPostalCode ?? cityPostal;
      if ((streetController.text).trim().isEmpty && nextStreet != null && nextStreet.isNotEmpty) {
        streetController.text = nextStreet;
      }
    });
  }

  String? _mapCityFromRawText(String raw) {
    final t = raw.toLowerCase();
    if (t.contains("mandaue")) return "Mandaue";
    if (t.contains("lapu") && (t.contains("lapu-lapu") || t.contains("lapu l") || t.contains("lapulapu"))) {
      return "Lapu-Lapu";
    }
    if (t.contains("lapu-lapu") || t.contains("lapu lapu")) return "Lapu-Lapu";
    return null;
  }

  String? _matchBarangayFromRawText(String? rawSubLocality, String? city) {
    if (city == null) return null;
    if (rawSubLocality == null) return null;

    final sub = rawSubLocality.trim();
    if (sub.isEmpty) return null;

    final candidates = barangaysByCity[city];
    if (candidates == null || candidates.isEmpty) return null;

    // Exact match first.
    if (candidates.contains(sub)) return sub;

    // Fuzzy contains match (case-insensitive).
    final lowerSub = sub.toLowerCase();
    for (final b in candidates) {
      if (lowerSub.contains(b.toLowerCase())) return b;
    }
    return null;
  }

  String _guessCityByDistance(LatLng coords) {
    // Centers are approximate and only used as a fallback when reverse geocoding fails.
    const mandaueCenter = LatLng(10.3400, 123.9494);
    const lapuLapuCenter = LatLng(10.3125, 123.9705);

    final dM = Geolocator.distanceBetween(
      coords.latitude,
      coords.longitude,
      mandaueCenter.latitude,
      mandaueCenter.longitude,
    );
    final dL = Geolocator.distanceBetween(
      coords.latitude,
      coords.longitude,
      lapuLapuCenter.latitude,
      lapuLapuCenter.longitude,
    );
    return dM <= dL ? "Mandaue" : "Lapu-Lapu";
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Color(0xFF1C1B1F),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter> inputFormatters = const [],
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: _boxDecoration(),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF1C1B1F),
          fontWeight: FontWeight.w500,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

Widget _disabledField(String value) {
  return Container(
    height: 46,
    padding: const EdgeInsets.symmetric(horizontal: 15),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12), // optional
      border: Border.all(color: Colors.transparent, width: 0), // removes border
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: const TextStyle(fontSize: 15, color: Colors.grey),
      ),
    ),
  );
}

  // ------------------ UPDATED DROPDOWN ------------------
  Widget _dropdown(
    String selectedValue,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      alignment: Alignment.center,
      decoration: _boxDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(selectedValue) ? selectedValue : null,
          isExpanded: true,

          // REMOVE DEFAULT ARROW
          iconSize: 0,

          // CUSTOM ARROW (GRAY + MOVE LEFT)
          icon: Transform.translate(
            offset: const Offset(6, 0), // adjust left position
            child: const Icon(
              Icons.arrow_drop_down,
              color: Color(0xFFACACAC),
              size: 26,
            ),
          ),

          dropdownColor: Colors.white,

          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),

          items: items.map((value) {
            return DropdownMenuItem(
              value: value,
              child: Text(
                value,
                style: const TextStyle(color: Colors.black, fontSize: 14),
              ),
            );
          }).toList(),

          onChanged: onChanged,
        ),
      ),
    );
  }

  BoxDecoration _boxDecoration({Color color = Colors.white}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xffD9D9D9)),
    );
  }
}

/// Full address form for Profile → Address Details: Add or Edit. Saves and pops back with result.
class AddressFormPage extends StatefulWidget {
  const AddressFormPage({super.key, this.initialAddress});

  /// When non-null, form is pre-filled for editing.
  final Map<String, dynamic>? initialAddress;

  @override
  State<AddressFormPage> createState() => _AddressFormPageState();
}

class _AddressFormPageState extends State<AddressFormPage> {
  late TextEditingController firstNameController;
  late TextEditingController lastNameController;
  late TextEditingController contactController;
  late TextEditingController streetController;
  int selectedLabelIndex = 0;
  static const String _provinceCebu = "Cebu";
  String selectedCity = ""; // "" = "Select City"
  String selectedBarangay = ""; // "" = "Select Barangay"

  static const List<String> _cities = ["Mandaue", "Lapu-Lapu"];
  static const Map<String, List<String>> _barangaysByCity = {
    "Mandaue": [
      "Alang-Alang", "Bakilid", "Banilad", "Basak", "Cabancalan", "Cambaro",
      "Canduman", "Centro", "Guizo", "Ibabao-Estancia", "Jagobiao", "Labogon",
      "Looc", "Maguikay", "Mantuyong", "Opao", "Pagsabungan", "Subangdaku",
      "Tabok", "Tawason", "Tipolo", "Umapad",
    ],
    "Lapu-Lapu": [
      "Agus", "Babag", "Bankal", "Basak", "Buaya", "Canjulao", "Gun-ob", "Ibo",
      "Looc", "Mactan", "Maribago", "Marigondon", "Pajac", "Pajo", "Poblacion",
      "Punta Engaño", "Pusok", "Subabasbas", "Talima", "Tingo",
    ],
  };

  String get postalCode =>
      selectedCity == "Mandaue" ? "6014" : (selectedCity == "Lapu-Lapu" ? "6015" : "");

  @override
  void initState() {
    super.initState();
    final a = widget.initialAddress;
    final first = (a?["firstName"] ?? a?["firstname"] ?? "").toString().trim();
    final last = (a?["lastName"] ?? a?["lastname"] ?? "").toString().trim();
    final contact = (a?["contact"] ?? a?["contact_no"] ?? "").toString().trim();
    streetController = TextEditingController(text: (a?["street"] ?? a?["street_name"] ?? "").toString().trim());
    firstNameController = TextEditingController(text: first);
    lastNameController = TextEditingController(text: last);
    contactController = TextEditingController(text: contact);
    final normalizedContact = normalizeContactDigits(contact);
    if (normalizedContact != null) {
      contactController.text = normalizedContact;
    }
    final digitsForCap = contactController.text.replaceAll(RegExp(r'\D'), '');
    if (digitsForCap.length > 11) {
      contactController.text = digitsForCap.substring(0, 11);
    }
    if (a != null) {
      final city = (a["city"] ?? "").toString().trim();
      final barangay = (a["barangay"] ?? "").toString().trim();
      if (_cities.contains(city)) selectedCity = city;
      if (selectedCity.isNotEmpty && barangay.isNotEmpty &&
          (_barangaysByCity[selectedCity] ?? []).contains(barangay)) {
        selectedBarangay = barangay;
      }
      final label = (a["label"] ?? a["label_as"] ?? "").toString();
      if (label == "Home") selectedLabelIndex = 0;
      else if (label == "Work") selectedLabelIndex = 1;
      else if (label == "Other") selectedLabelIndex = 2;
    }
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    contactController.dispose();
    streetController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _toSavedAddress() {
    final labels = ["Home", "Work", "Other"];
    final street = streetController.text.trim();
    final city = selectedCity;
    final barangay = selectedBarangay;
    final fullAddress = street.isEmpty && city.isEmpty && barangay.isEmpty
        ? ""
        : "$street, $barangay, ${city.isNotEmpty ? "$city City, " : ""}$_provinceCebu, $postalCode".replaceAll(RegExp(r',\s*,'), ', ').trim();
    final map = <String, dynamic>{
      "firstName": firstNameController.text.trim(),
      "lastName": lastNameController.text.trim(),
      "contact": contactController.text.trim(),
      "street": street,
      "province": _provinceCebu,
      "city": city,
      "barangay": barangay,
      "postalCode": postalCode,
      "label": labels[selectedLabelIndex.clamp(0, 2)],
      "fullAddress": fullAddress,
    };
    final id = widget.initialAddress?["id"];
    // Firestore document IDs are often non-numeric strings, so keep as String.
    if (id != null) {
      map["id"] = id.toString();
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 43,
        leading: Transform.translate(
          offset: const Offset(20, 0),
          child: SizedBox(
            child: Material(
              color: const Color(0xFFF2F2F2),
              shape: const CircleBorder(),
              clipBehavior: Clip.hardEdge,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context),
                child: const Center(child: Icon(Icons.arrow_back, size: 20, color: Colors.black)),
              ),
            ),
          ),
        ),
        title: Container(
          height: 43,
          width: 160,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            widget.initialAddress != null ? "Edit Address" : "Add Address",
            style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 15.69, color: Colors.black),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_formLabel("First Name"), _formTextField(firstNameController)])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_formLabel("Last Name"), _formTextField(lastNameController)])),
                ],
              ),
              const SizedBox(height: 8),
              _formLabel("Contact Number"),
              _formTextField(
                contactController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_formLabel("Province"), _formDisabledField(_provinceCebu)])),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formLabel("City"),
                        _formDropdownWithPlaceholder(
                          selectedCity,
                          ["", ..._cities],
                          "Select City",
                          (v) => setState(() {
                            selectedCity = v ?? "";
                            selectedBarangay = "";
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formLabel("Barangay"),
                        _formDropdownWithPlaceholder(
                          selectedBarangay,
                          selectedCity.isEmpty
                              ? [""]
                              : ["", ...(_barangaysByCity[selectedCity] ?? [])],
                          "Select Barangay",
                          (v) => setState(() => selectedBarangay = v ?? ""),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formLabel("Postal Code"),
                        _formDisabledField(postalCode.isEmpty ? "—" : postalCode),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _formLabel("Street Name, Building, House No."),
              _formTextField(streetController),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final result = await Navigator.push<dynamic>(
                    context,
                    MaterialPageRoute(builder: (_) => const MapPickerPage()),
                  );

                  if (!mounted) return;
                  if (result is LatLng) {
                    await _applyPickedLocationToForm(result);
                  }
                },
                child: Container(
                  height: 114,
                  decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(12)),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 18),
                      decoration: BoxDecoration(color: const Color(0xFFE5E5E5), borderRadius: BorderRadius.circular(8)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add, color: Color(0xff949494)),
                        SizedBox(width: 6),
                        Text("Add Location", style: TextStyle(color: Color(0xff949494), fontSize: 12.55, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _formLabel("Label as:"),
              const SizedBox(height: 6),
              Row(
                children: List.generate(3, (index) {
                  final labels = ["Home", "Work", "Other"];
                  final isSelected = selectedLabelIndex == index;
                  return Padding(
                    padding: EdgeInsets.only(right: index != 2 ? 10 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() => selectedLabelIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: isSelected ? const Color(0xFFE3001B) : Colors.white,
                          border: Border.all(color: isSelected ? Colors.transparent : const Color(0xFFDEDEDE)),
                        ),
                        child: Text(labels[index], style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF1C1B1F), fontSize: 14, fontWeight: FontWeight.w400)),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 11),
              GestureDetector(
                onTap: () {
                  if (selectedCity.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a city.'), behavior: SnackBarBehavior.floating));
                    return;
                  }
                  if (selectedBarangay.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a barangay.'), behavior: SnackBarBehavior.floating));
                    return;
                  }
                  final normalizedContact = normalizeContactDigits(contactController.text);
                  if (normalizedContact == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Contact number must be 10-11 digits and start with 9 (e.g. 9945936764).'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  if (contactController.text != normalizedContact) {
                    contactController.text = normalizedContact;
                  }
                  Navigator.pop(context, _toSavedAddress());
                },
                child: Container(
                  height: 55,
                  decoration: BoxDecoration(color: const Color(0xFFE3001B), borderRadius: BorderRadius.circular(35)),
                  child: const Center(child: Text("Save & Continue", style: TextStyle(color: Colors.white, fontSize: 16))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyPickedLocationToForm(LatLng coords) async {
    String? nextCity;
    String? nextBarangay;
    String? nextStreet;

    try {
      final placemarks = await placemarkFromCoordinates(
        coords.latitude,
        coords.longitude,
      );
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final rawCity = [pm.locality, pm.subAdministrativeArea, pm.administrativeArea]
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .join(", ");
        nextCity = _mapCityFromRawTextInAddress(rawCity);
        nextBarangay = _matchBarangayFromRawTextInAddress(pm.subLocality, nextCity);
        nextStreet = (pm.thoroughfare ?? pm.name ?? "").trim();
      }
    } catch (_) {
      // ignore; fallback below
    }

    nextCity ??= _guessCityByDistanceInAddress(coords);
    if (!_cities.contains(nextCity)) return;

    final nextBarangayFallback = (_barangaysByCity[nextCity] ?? const <String>[]).isNotEmpty
        ? (_barangaysByCity[nextCity] ?? const <String>[]).first
        : "";
    nextBarangay ??= nextBarangayFallback;

    if (!mounted) return;
    setState(() {
      selectedCity = nextCity ?? selectedCity;
      selectedBarangay = nextBarangay ?? selectedBarangay;
      if (streetController.text.trim().isEmpty && nextStreet != null && nextStreet.isNotEmpty) {
        streetController.text = nextStreet;
      }
    });
  }

  String? _mapCityFromRawTextInAddress(String raw) {
    final t = raw.toLowerCase();
    if (t.contains("mandaue")) return "Mandaue";
    if (t.contains("lapu") && (t.contains("lapu-lapu") || t.contains("lapu lapu") || t.contains("lapulapu"))) {
      return "Lapu-Lapu";
    }
    if (t.contains("lapu-lapu") || t.contains("lapu lapu")) return "Lapu-Lapu";
    return null;
  }

  String? _matchBarangayFromRawTextInAddress(String? rawSubLocality, String? city) {
    if (city == null) return null;
    if (rawSubLocality == null) return null;
    final sub = rawSubLocality.trim();
    if (sub.isEmpty) return null;

    final candidates = _barangaysByCity[city];
    if (candidates == null || candidates.isEmpty) return null;

    if (candidates.contains(sub)) return sub;

    final lowerSub = sub.toLowerCase();
    for (final b in candidates) {
      if (lowerSub.contains(b.toLowerCase())) return b;
    }
    return null;
  }

  String _guessCityByDistanceInAddress(LatLng coords) {
    const mandaueCenter = LatLng(10.3400, 123.9494);
    const lapuLapuCenter = LatLng(10.3125, 123.9705);

    final dM = Geolocator.distanceBetween(
      coords.latitude,
      coords.longitude,
      mandaueCenter.latitude,
      mandaueCenter.longitude,
    );
    final dL = Geolocator.distanceBetween(
      coords.latitude,
      coords.longitude,
      lapuLapuCenter.latitude,
      lapuLapuCenter.longitude,
    );
    return dM <= dL ? "Mandaue" : "Lapu-Lapu";
  }

  Widget _formLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF1C1B1F))),
    );
  }

  Widget _formTextField(
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter> inputFormatters = const [],
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xffD9D9D9))),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1C1B1F), fontWeight: FontWeight.w500),
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true, contentPadding: EdgeInsets.zero),
      ),
    );
  }

  Widget _formDropdownWithPlaceholder(String selectedValue, List<String> items, String placeholderLabel, Function(String?) onChanged) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xffD9D9D9))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(selectedValue) ? selectedValue : items.first,
          isExpanded: true,
          iconSize: 0,
          icon: Transform.translate(offset: const Offset(6, 0), child: const Icon(Icons.arrow_drop_down, color: Color(0xFFACACAC), size: 26)),
          dropdownColor: Colors.white,
          style: TextStyle(color: selectedValue.isEmpty ? Colors.grey : Colors.black, fontSize: 14, fontWeight: FontWeight.w500),
          items: items.map((v) {
            return DropdownMenuItem<String>(
              value: v,
              child: Text(v.isEmpty ? placeholderLabel : v, style: TextStyle(color: v.isEmpty ? Colors.grey : Colors.black, fontSize: 14)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _formDisabledField(String value) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.transparent, width: 0)),
      alignment: Alignment.centerLeft,
      child: Text(value, style: const TextStyle(fontSize: 15, color: Colors.grey)),
    );
  }
}

/// Normalizes a PH phone number to local digits only.
/// Rules:
/// - Keeps digits only (strips spaces, `+`, etc).
/// - If input starts with `63`, it strips the `63` prefix (for pasted `+63 ...`).
/// - The remaining number must be 10-11 digits and start with `9`.
/// - Returns normalized digits (starting with `9`) or `null` if invalid.
String? normalizeContactDigits(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  var candidate = digits;
  if (candidate.startsWith('63')) {
    candidate = candidate.substring(2);
  }

  // Reject local numbers that start with 0.
  if (candidate.startsWith('0')) return null;

  if (!(candidate.length == 10 || candidate.length == 11)) return null;
  if (!candidate.startsWith('9')) return null;
  return candidate;
}
