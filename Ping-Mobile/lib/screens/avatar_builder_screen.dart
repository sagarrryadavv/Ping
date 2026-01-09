import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'home_screen.dart';

// ⚠️ KEEP YOUR ASSET IMPORTS
import '../assets/fluttermoji_assets/style.dart';
import '../assets/fluttermoji_assets/skin.dart';
import '../assets/fluttermoji_assets/top/hairStyles/hairStyle.dart';
import '../assets/fluttermoji_assets/clothes/clothes.dart';
import '../assets/fluttermoji_assets/face/eyes/eyes.dart';
import '../assets/fluttermoji_assets/face/eyebrow/eyebrow.dart';
import '../assets/fluttermoji_assets/face/mouth/mouth.dart';
import '../assets/fluttermoji_assets/face/nose/nose.dart';
import '../assets/fluttermoji_assets/top/facialHair/facialHair.dart';
import '../assets/fluttermoji_assets/top/accessories/accessories.dart';

class AvatarBuilderScreen extends StatefulWidget {
  final bool isFirstTime;
  // ⚠️ BUG 3 FIX: Accept existing config
  final Map<String, dynamic>? currentConfig;

  const AvatarBuilderScreen({
    super.key,
    this.isFirstTime = false,
    this.currentConfig, // Optional: Null if first time
  });

  @override
  State<AvatarBuilderScreen> createState() => _AvatarBuilderScreenState();
}

class _AvatarBuilderScreenState extends State<AvatarBuilderScreen> {
  // 1. Categories
  final List<Map<String, dynamic>> categories = [
    {"name": "Skin", "param": "skinColor"},
    {"name": "Hair", "param": "topType"},
    {"name": "H-Color", "param": "hairColor"},
    {"name": "Eyes", "param": "eyeType"},
    {"name": "Brows", "param": "eyebrowType"},
    {"name": "Mouth", "param": "mouthType"},
    {"name": "Beard", "param": "facialHairType"},
    {"name": "Clothes", "param": "clotheType"},
    {"name": "C-Color", "param": "clotheColor"},
    {"name": "Acc", "param": "accessoriesType"},
  ];

  // 2. Default Selections (Fallback)
  Map<String, String> currentSelections = {
    "skinColor": "Peach",
    "topType": "Short n waved",
    "hairColor": "Brown",
    "eyeType": "Happy",
    "eyebrowType": "Default",
    "mouthType": "Smile",
    "facialHairType": "Nothing",
    "clotheType": "Hoodie",
    "clotheColor": "Red",
    "accessoriesType": "Nothing",
    "style": "Circle",
  };

  int _selectedCategoryIndex = 1;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // ⚠️ BUG 3 FIX: Load existing avatar if available
    if (widget.currentConfig != null) {
      widget.currentConfig!.forEach((key, value) {
        // Only update known keys to prevent crashes from bad data
        if (currentSelections.containsKey(key)) {
          currentSelections[key] = value.toString();
        }
      });
    }
  }

  // --- BUILD MAIN AVATAR SVG ---
  String _buildAvatarSvg() {
    String _style = fluttermojiStyle['Circle']!;
    String _hair = HairStyle.generateHairStyle(
            hairType: currentSelections['topType']!,
            hColor: currentSelections['hairColor']!) ??
        "";
    String _clothes = Clothes.generateClothes(
            clotheType: currentSelections['clotheType']!,
            clColor: currentSelections['clotheColor']!) ??
        "";
    String _beard = FacialHair.generateFacialHair(
            facialHairType: currentSelections['facialHairType']!,
            fhColor: "Black") ??
        "";
    String _skin = skin[currentSelections['skinColor']] ?? "";
    String _eyes = eyes[currentSelections['eyeType']] ?? "";
    String _brows = eyebrow[currentSelections['eyebrowType']] ?? "";
    String _mouth = mouth[currentSelections['mouthType']] ?? "";
    String _nose = nose['Default'] ?? "";
    String _access = accessories[currentSelections['accessoriesType']] ?? "";

    return '''
<svg width="264px" height="280px" viewBox="0 0 264 280" version="1.1" xmlns="http://www.w3.org/2000/svg">
  <g stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">
    <g transform="translate(-825.000000, -1100.000000)">
      <g transform="translate(825.000000, 1100.000000)">
        $_style
        <g transform="translate(32.000000, 36.000000)">$_skin</g>
        $_clothes
        <g transform="translate(76.000000, 82.000000)" fill="#000000">
          $_mouth $_beard $_nose $_eyes $_brows $_access
        </g>
        $_hair
      </g>
    </g>
  </g>
</svg>
''';
  }

  // --- BUILD MINI PREVIEW FOR GRID ---
  String _buildItemPreview(String param, String optionKey) {
    String content = "";

    if (param == "topType")
      content =
          HairStyle.generateHairStyle(hairType: optionKey, hColor: "Black") ??
              "";
    else if (param == "clotheType")
      content =
          Clothes.generateClothes(clotheType: optionKey, clColor: "Blue02") ??
              "";
    else if (param == "facialHairType")
      content = FacialHair.generateFacialHair(
              facialHairType: optionKey, fhColor: "Black") ??
          "";
    else if (param == "eyeType")
      content = eyes[optionKey] ?? "";
    else if (param == "eyebrowType")
      content = eyebrow[optionKey] ?? "";
    else if (param == "mouthType")
      content = mouth[optionKey] ?? "";
    else if (param == "accessoriesType")
      content = accessories[optionKey] ?? "";
    else if (param == "skinColor") content = skin[optionKey] ?? "";

    return '''
<svg width="60px" height="60px" viewBox="0 0 264 280" version="1.1" xmlns="http://www.w3.org/2000/svg">
  <g stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">
    <g transform="translate(-825.000000, -1100.000000)">
      <g transform="translate(825.000000, 1100.000000)">
        $content
      </g>
    </g>
  </g>
</svg>
''';
  }

  Future<void> _saveAvatarToCloud() async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String avatarData = _buildAvatarSvg();

      // ⚠️ Save both the SVG string AND the config map
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        "avatarData": avatarData,
        "isOfflineAvatar": true,
        "avatarConfig": currentSelections, // This is what we load back later
        "avatarSetupComplete": true,
        "lastActive": DateTime.now(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<String> _getOptionsForCurrentCategory() {
    String param = categories[_selectedCategoryIndex]['param'];
    switch (param) {
      case "skinColor":
        return skin.keys.toList();
      case "topType":
        return [
          'Bald',
          'Short n waved',
          'Short n curly',
          'The caesar',
          'Short w/ dreads',
          'Bob cut',
          'Bun',
          'Fro',
          'Long (Female)',
          'Curvy',
          'Shaggy',
          'Short w/ frizzle',
          'LongHairStraight',
          'Curly (Female)',
          'Long w/ dreads',
          'Frida',
          'Fro w/ band',
          'Long w/ shaved sides',
          'Mia Wallace',
          'WinterHat1',
          'WinterHat2',
          'Santa Hat'
        ];
      case "hairColor":
        return HairStyle.hairColor.keys.toList();
      case "eyeType":
        return eyes.keys.toList();
      case "eyebrowType":
        return eyebrow.keys.toList();
      case "mouthType":
        return mouth.keys.toList();
      case "facialHairType":
        return [
          "Nothing",
          "Full Beard",
          "Beard, Light",
          "Moustache, Fancy",
          "That 80's moustache"
        ];
      case "clotheType":
        return [
          "Hoodie",
          "Blazer + T-Shirt",
          "BlazerSweater",
          "CollarSweater",
          "GraphicShirt",
          "Overall",
          "Crew Neck Tee",
          "Scoop-neck Tee",
          "ShirtVNeck"
        ];
      case "clotheColor":
        return Clothes.clotheColor.keys.toList();
      case "accessoriesType":
        return accessories.keys.toList();
      default:
        return [];
    }
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll("#", "");
    if (hex.length == 6) hex = "FF$hex";
    return Color(int.parse(hex, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    String currentParam = categories[_selectedCategoryIndex]['param'];
    List<String> currentOptions = _getOptionsForCurrentCategory();
    bool isColorSelection = currentParam.contains("Color");

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!widget.isFirstTime)
                    IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context))
                  else
                    SizedBox(width: 48),
                  Text("CUSTOMIZE",
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.5)),
                  SizedBox(width: 48),
                ],
              ),
            ),

            // 1. AVATAR PREVIEW
            Expanded(
              flex: 4,
              child: Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF3D2B5),
                    border:
                        Border.all(color: const Color(0xFFFFC0CB), width: 4),
                  ),
                  child: ClipOval(
                    child: Transform.scale(
                      scale: 1.35,
                      alignment: Alignment.center,
                      child: SvgPicture.string(
                        _buildAvatarSvg(),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. CATEGORY SELECTOR
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  bool isSelected = index == _selectedCategoryIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategoryIndex = index),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFC0CB)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : Colors.white24),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        categories[index]['name'],
                        style: GoogleFonts.poppins(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 15),

            // 3. GRID
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF151515),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: currentOptions.length,
                  itemBuilder: (context, index) {
                    String optionKey = currentOptions[index];
                    bool isSelected =
                        currentSelections[currentParam] == optionKey;
                    Color? tileColor;
                    String? svgPreview;

                    if (isColorSelection) {
                      String? hex;
                      if (currentParam == 'hairColor')
                        hex = HairStyle.hairColor[optionKey];
                      if (currentParam == 'clotheColor')
                        hex = Clothes.clotheColor[optionKey];
                      if (hex != null) tileColor = _hexToColor(hex);
                    } else {
                      svgPreview = _buildItemPreview(currentParam, optionKey);
                    }

                    return GestureDetector(
                      onTap: () => setState(
                          () => currentSelections[currentParam] = optionKey),
                      child: Container(
                        decoration: BoxDecoration(
                          color: tileColor ??
                              (isSelected
                                  ? const Color(0xFFFFC0CB)
                                  : const Color(0xFF3A2A2C)),
                          borderRadius: BorderRadius.circular(16),
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (svgPreview != null)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: SvgPicture.string(svgPreview,
                                      fit: BoxFit.contain),
                                ),
                              ),
                            if (svgPreview != null || tileColor == null)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 8.0, left: 4, right: 4),
                                child: Text(
                                  optionKey.length > 10
                                      ? "${optionKey.substring(0, 8)}.."
                                      : optionKey,
                                  style: TextStyle(
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
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

            // 4. SAVE BUTTON
            Container(
              color: const Color(0xFF151515),
              padding: const EdgeInsets.fromLTRB(25, 0, 25, 25),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC0CB),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  onPressed: _isSaving ? null : _saveAvatarToCloud,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text("FINISH & SAVE",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
