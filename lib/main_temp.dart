// ================================================================
// ROUTE MASTER ERP v4.0 - SINGLE MASTER FILE
// ================================================================
// pubspec.yaml dependencies:
//   http: ^1.1.0
//   shared_preferences: ^2.2.2
//   pdf: ^3.10.7
//   printing: ^5.12.0
//   image_picker: ^1.0.4          (for camera / gallery)
//   file_picker: ^6.1.1           (for document upload)
//   url_launcher: ^6.2.4          (for sharing docs)
//   path_provider: ^2.1.2         (for temp file storage)
// ================================================================
// ADMIN ACCESS: Tap "ROUTE MASTER" in AppBar 7Ã— within 3 seconds
// DEV PIN: RM@Dev#2025! (change before going live)
// OCR: Uses Google Cloud Vision API â€” enable it in Google Cloud Console
// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'firebase_options.dart';
// OCR via Google Cloud Vision API (uses existing Maps API key billing)

// ================================================================
// CONFIG
// ================================================================
class AppConfig {
  // Developer master PIN â€” NEVER shown to fleet owner. Change before going live.
  static const String _adminPin = "170219";
  static const String googleMapsApiKey =
      "AIzaSyCNDe3Sc9VWXFqW76PibKHlBN6vhKmaLXU";
  static const String appVersion = "4.0.0";
  static const int adminTapCount = 1; // long press triggers directly
  static const int adminTapWindowMs = 3000;
  static const double defaultDieselPrice = 92.0;
  static const int paymentAlertDays = 5;
  static bool validatePin(String p) => p == _adminPin;
  static bool get hasGoogleMaps =>
      googleMapsApiKey.isNotEmpty && googleMapsApiKey.length > 20;
}

// ================================================================
// FIREBASE SERVICE â€” wraps all Firebase calls
// ================================================================
class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static FirebaseAuth get auth => _auth;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static bool _ready = false;

  static bool get isReady => _ready;
  static User? get currentUser => _auth.currentUser;

  static Future<void> init() async {
    try {
      _ready = Firebase.apps.isNotEmpty;
    } catch (_) {
      _ready = false;
    }
  }

  // â”€â”€ OTP PHONE AUTH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> sendOTP({
    required String phone,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  }) async {
    if (!_ready) {
      onError(
          "Firebase not initialized. Check google-services.json is in android/app/");
      return;
    }
    // Validate phone format
    final cleaned = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!cleaned.startsWith('+91') || cleaned.length != 13) {
      onError("Invalid phone number. Must be 10 digits with +91 prefix.");
      return;
    }
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: cleaned,
        timeout: const Duration(seconds: 120),
        verificationCompleted: (PhoneAuthCredential cred) async {
          // Auto-verify on Android via SMS Retriever API
          try {
            await _auth.signInWithCredential(cred);
            onCodeSent('AUTO_VERIFIED'); // signal auto-verification
          } catch (e) {
            debugPrint('Auto-verify failed: $e');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('Firebase OTP error: ${e.code} â€” ${e.message}');
          String msg;
          switch (e.code) {
            case 'invalid-phone-number':
              msg = 'Invalid number. Enter 10 digits without country code.';
              break;
            case 'too-many-requests':
              msg = 'Too many attempts. Wait 1 hour and try again.';
              break;
            case 'app-not-authorized':
              msg =
                  'SHA-1 mismatch. Add debug SHA-1 in Firebase Console â†’ Project Settings â†’ Android app â†’ Add fingerprint.';
              break;
            case 'quota-exceeded':
              msg = 'Daily SMS limit reached. Try tomorrow.';
              break;
            case 'billing-not-enabled':
              msg =
                  'Enable Blaze plan in Firebase Console for production OTPs.';
              break;
            case 'network-request-failed':
              msg = 'No internet connection. Check network and retry.';
              break;
            default:
              msg = e.message ??
                  'OTP failed (${e.code}). Check Firebase Console.';
          }
          onError(msg);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('OTP sent successfully to $cleaned');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('OTP auto-retrieval timeout â€” manual entry still works');
        },
      );
    } catch (e) {
      debugPrint('sendOTP exception: $e');
      onError(
          'Connection error: ${e.toString().split('(').first}. Retry or check internet.');
    }
  }

  static Future<bool> verifyOTP(
      {required String verificationId, required String otp}) async {
    try {
      final cred = PhoneAuthProvider.credential(
          verificationId: verificationId, smsCode: otp.trim());
      await _auth.signInWithCredential(cred);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint("OTP verify error: ${e.code} â€” ${e.message}");
      return false;
    } catch (_) {
      return false;
    }
  }

  // â”€â”€ FIRESTORE â€” sync ledgers, fleet, drivers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static String get _uid => currentUser?.uid ?? 'local';

  static Future<void> saveLedgers(List<TripLedger> ledgers) async {
    if (!_ready || currentUser == null) return;
    try {
      final batch = _db.batch();
      final col = _db.collection('users/$_uid/ledgers');
      for (final l in ledgers) {
        batch.set(col.doc(l.id), l.toJson());
      }
      await batch.commit();
    } catch (_) {}
  }

  static Future<List<TripLedger>> loadLedgers() async {
    if (!_ready || currentUser == null) return [];
    try {
      final snap = await _db
          .collection('users/$_uid/ledgers')
          .orderBy('date', descending: true)
          .get();
      return snap.docs.map((d) => TripLedger.fromJson(d.data())).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveDrivers(List<Driver> drivers) async {
    if (!_ready || currentUser == null) return;
    try {
      final batch = _db.batch();
      final col = _db.collection('users/$_uid/drivers');
      for (final d in drivers) {
        batch.set(col.doc(d.id), d.toJson());
      }
      await batch.commit();
    } catch (_) {}
  }

  static Future<void> saveFleet(List<Asset> fleet) async {
    if (!_ready || currentUser == null) return;
    try {
      final batch = _db.batch();
      final col = _db.collection('users/$_uid/fleet');
      for (final a in fleet) {
        batch.set(col.doc(a.id), a.toJson());
      }
      await batch.commit();
    } catch (_) {}
  }

  // â”€â”€ FIREBASE STORAGE â€” upload documents â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<String?> uploadDocument(
      String localPath, String docName, String vehicleOrDriver) async {
    if (!_ready || currentUser == null) return null;
    try {
      final file = File(localPath);
      final ext = localPath.split('.').last;
      final ref = _storage
          .ref('$_uid/$vehicleOrDriver/${docName.replaceAll(' ', '_')}.$ext');
      final task = await ref.putFile(file);
      return await task.ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  // â”€â”€ ADMIN â€” developer dashboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<Map<String, dynamic>> getAdminStats() async {
    if (!_ready) return {};
    try {
      final users = await _db.collection('users').get();
      int totalTrips = 0;
      int totalFleet = 0;
      for (final u in users.docs) {
        final trips =
            await _db.collection('users/${u.id}/ledgers').count().get();
        final fleet = await _db.collection('users/${u.id}/fleet').count().get();
        totalTrips += trips.count ?? 0;
        totalFleet += fleet.count ?? 0;
      }
      return {
        'totalUsers': users.docs.length,
        'totalTrips': totalTrips,
        'totalFleet': totalFleet
      };
    } catch (_) {
      return {};
    }
  }

  // â”€â”€ OCR â€” reads text from document images via Google Cloud Vision API â”€â”€
  // Uses same API key as Maps (no extra setup needed)
  static Future<Map<String, String>> extractDocumentText(
      String imagePath) async {
    final result = <String, String>{};
    try {
      // Read image as base64
      final bytes = await File(imagePath).readAsBytes();
      final b64 = base64Encode(bytes);

      // Call Google Cloud Vision API - TEXT_DETECTION
      final url =
          'https://vision.googleapis.com/v1/images:annotate?key=${AppConfig.googleMapsApiKey}';
      final body = jsonEncode({
        'requests': [
          {
            'image': {'content': b64},
            'features': [
              {'type': 'TEXT_DETECTION', 'maxResults': 1}
            ]
          }
        ]
      });
      final res = await http
          .post(Uri.parse(url),
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        result['error'] = 'Vision API error ${res.statusCode}';
        return result;
      }
      final data = jsonDecode(res.body);
      final textAnnotations =
          data['responses']?[0]?['textAnnotations'] as List?;
      if (textAnnotations == null || textAnnotations.isEmpty) return result;

      final fullText =
          (textAnnotations[0]['description'] as String? ?? '').toUpperCase();
      final lines = fullText
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      // Engine Number
      for (final p in [
        RegExp(r'ENGINE\s*(?:NO|NUMBER|NUM|#)[\s:.]*([A-Z0-9]{6,20})'),
        RegExp(r'ENG\.?\s*NO[\s:.]*([A-Z0-9]{6,20})'),
      ]) {
        final m = p.firstMatch(fullText);
        if (m?.group(1) != null) {
          result['engineNo'] = m!.group(1)!.trim();
          break;
        }
      }

      // Chassis / VIN
      for (final p in [
        RegExp(r'CHASSIS\s*(?:NO|NUMBER|NUM)[\s:.]*([A-Z0-9]{10,20})'),
        RegExp(r'(?:VIN|FRAME\s*NO)[\s:.]*([A-Z0-9]{10,20})'),
      ]) {
        final m = p.firstMatch(fullText);
        if (m?.group(1) != null) {
          result['chassisNo'] = m!.group(1)!.trim();
          break;
        }
      }

      // Registration Number
      final regM = RegExp(
              r'([A-Z]{2}[\s\-]?[0-9]{1,2}[\s\-]?[A-Z]{1,3}[\s\-]?[0-9]{1,4})')
          .firstMatch(fullText);
      if (regM != null) result['regNo'] = regM.group(0)!.replaceAll(' ', '-');

      // Expiry date
      for (final p in [
        RegExp(
            r'(?:VALID\s*UPTO?|EXPIR\w*\s*DATE?|UPTO)[\s:.]*([0-9]{1,2}[/\-][0-9]{1,2}[/\-][0-9]{2,4})'),
        RegExp(r'([0-9]{2}[/\-][0-9]{2}[/\-][0-9]{4})'),
      ]) {
        final m = p.firstMatch(fullText);
        if (m?.group(1) != null) {
          result['expiryDate'] = m!.group(1)!.trim();
          break;
        }
      }

      // Insurance company
      final insurerM = RegExp(
              r'(NEW INDIA|NATIONAL INSURANCE|UNITED INDIA|ORIENTAL|BAJAJ ALLIANZ|HDFC ERGO|ICICI LOMBARD|RELIANCE GENERAL|TATA AIG|ROYAL SUNDARAM|SBI GENERAL|IFFCO TOKIO|CHOLA MS)')
          .firstMatch(fullText);
      if (insurerM != null) result['insurer'] = insurerM.group(0)!;

      // Aadhaar â€” 12 digits in groups of 4
      final aadhaarM =
          RegExp(r'([0-9]{4}\s[0-9]{4}\s[0-9]{4})').firstMatch(fullText);
      if (aadhaarM != null) {
        result['aadhaarNo'] = aadhaarM.group(0)!.replaceAll(' ', '');
      }

      // DL number
      final dlM =
          RegExp(r'([A-Z]{2}[0-9]{2}\s?[0-9]{11})').firstMatch(fullText);
      if (dlM != null) result['dlNo'] = dlM.group(0)!.replaceAll(' ', '');

      // Owner name â€” line after OWNER/NAME
      for (int i = 0; i < lines.length - 1; i++) {
        if (lines[i].contains('OWNER') || lines[i].contains('NAME OF')) {
          final name = lines[i + 1].replaceAll(RegExp(r'[^A-Z\s]'), '').trim();
          if (name.length > 3) {
            result['ownerName'] = name;
            break;
          }
        }
      }
    } catch (e) {
      result['error'] = e.toString();
    }
    return result;
  }

  // â”€â”€ MARKET LOADS â€” shared across all users (load board) â”€â”€â”€â”€â”€â”€â”€
  static Stream<List<MarketLoad>> marketLoadsStream() {
    if (!_ready) return const Stream.empty();
    return _db
        .collection('marketLoads')
        .where('status', isEqualTo: 'pending')
        .orderBy('postedDate', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => MarketLoad.fromJson(d.data())).toList());
  }

  static Future<void> postMarketLoad(MarketLoad load) async {
    if (!_ready) return;
    try {
      await _db.collection('marketLoads').doc(load.id).set({
        ...load.toJson(),
        'postedBy': _uid,
        'status': 'pending',
      });
    } catch (_) {}
  }
}

// ================================================================
// ENUMS
// ================================================================
enum UserRole { visitor, verified, admin }

enum BidStatus { pending, booked, inTransit, delivered, cancelled }

enum VehicleOwnership { self, market }

enum DriverTxType { advance, salary, penalty, fuel, bonus, deduction }

enum SubscriptionTier { free, pro, business, enterprise }

enum KredXStatus {
  draft,
  submitted,
  underReview,
  approved,
  disbursed,
  rejected
}

enum TripStatus { active, completed, overdue }

enum GstType { none, cgstSgst, igst }

enum DocUploadMethod { camera, gallery, file }

// ================================================================
// VEHICLE COMPLIANCE DOCS BY TYPE
// ================================================================
class VehicleDocConfig {
  static List<String> getRequiredDocs(String vehicleType) {
    final vt = vehicleType.toLowerCase().trim();
    final common = [
      "RC Book",
      "Insurance",
      "PUCC / Emission",
      "Fitness Certificate",
      "National Permit"
    ];
    if (vt.contains('tanker') || vt.contains('ss') || vt.contains('ms')) {
      return [
        ...common,
        "Explosive / Hazmat Auth",
        "Dangerous Goods Permit",
        "ADR Certificate",
        "Tank Calibration Certificate",
        "Tank Inspection Report",
        "Driver Hazmat Training"
      ];
    }
    if (vt.contains('container')) {
      return [
        ...common,
        "Container Seal Certificate",
        "Port Pass (if applicable)"
      ];
    }
    if (vt.contains('trailer') || vt.contains('abnormal')) {
      return [
        ...common,
        "Overloading Permit",
        "Abnormal Load Permit",
        "Pilot Vehicle Auth"
      ];
    }
    if (vt.contains('reefer') || vt.contains('refrigerated')) {
      return [
        ...common,
        "Cold Chain Certificate",
        "Temperature Log Book",
        "Reefer Unit Service Record"
      ];
    }
    if (vt.contains('lcv') || vt.contains('light')) {
      return ["RC Book", "Insurance", "PUCC / Emission", "National Permit"];
    }
    if (vt.contains('open') || vt.contains('truck')) {
      return [...common, "Weight Bridge Slip (per trip)"];
    }
    return common;
  }
}

// ================================================================
// INDIA DATA
// ================================================================
const List<Map<String, String>> kIndianCities = [
  {'city': 'Ahmedabad', 'state': 'Gujarat', 'full': 'Ahmedabad, Gujarat'},
  {'city': 'Surat', 'state': 'Gujarat', 'full': 'Surat, Gujarat'},
  {'city': 'Vadodara', 'state': 'Gujarat', 'full': 'Vadodara, Gujarat'},
  {'city': 'Rajkot', 'state': 'Gujarat', 'full': 'Rajkot, Gujarat'},
  {'city': 'Gandhinagar', 'state': 'Gujarat', 'full': 'Gandhinagar, Gujarat'},
  {'city': 'Bharuch', 'state': 'Gujarat', 'full': 'Bharuch, Gujarat'},
  {'city': 'Ankleshwar', 'state': 'Gujarat', 'full': 'Ankleshwar, Gujarat'},
  {'city': 'Hazira', 'state': 'Gujarat', 'full': 'Hazira, Gujarat'},
  {'city': 'Dahej', 'state': 'Gujarat', 'full': 'Dahej, Gujarat'},
  {'city': 'Mundra Port', 'state': 'Gujarat', 'full': 'Mundra Port, Gujarat'},
  {'city': 'Kandla Port', 'state': 'Gujarat', 'full': 'Kandla Port, Gujarat'},
  {'city': 'Vapi', 'state': 'Gujarat', 'full': 'Vapi, Gujarat'},
  {'city': 'Morbi', 'state': 'Gujarat', 'full': 'Morbi, Gujarat'},
  {'city': 'Bhavnagar', 'state': 'Gujarat', 'full': 'Bhavnagar, Gujarat'},
  {'city': 'Jamnagar', 'state': 'Gujarat', 'full': 'Jamnagar, Gujarat'},
  {'city': 'Mehsana', 'state': 'Gujarat', 'full': 'Mehsana, Gujarat'},
  {'city': 'Navsari', 'state': 'Gujarat', 'full': 'Navsari, Gujarat'},
  {'city': 'Anand', 'state': 'Gujarat', 'full': 'Anand, Gujarat'},
  {'city': 'Nadiad', 'state': 'Gujarat', 'full': 'Nadiad, Gujarat'},
  {
    'city': 'Surendranagar',
    'state': 'Gujarat',
    'full': 'Surendranagar, Gujarat'
  },
  {'city': 'Botad', 'state': 'Gujarat', 'full': 'Botad, Gujarat'},
  {'city': 'Amreli', 'state': 'Gujarat', 'full': 'Amreli, Gujarat'},
  {'city': 'Junagadh', 'state': 'Gujarat', 'full': 'Junagadh, Gujarat'},
  {'city': 'Porbandar', 'state': 'Gujarat', 'full': 'Porbandar, Gujarat'},
  {'city': 'Palanpur', 'state': 'Gujarat', 'full': 'Palanpur, Gujarat'},
  {'city': 'Himatnagar', 'state': 'Gujarat', 'full': 'Himatnagar, Gujarat'},
  {'city': 'Godhra', 'state': 'Gujarat', 'full': 'Godhra, Gujarat'},
  {'city': 'Bhuj', 'state': 'Gujarat', 'full': 'Bhuj, Gujarat'},
  {'city': 'Gandhidham', 'state': 'Gujarat', 'full': 'Gandhidham, Gujarat'},
  {'city': 'Veraval', 'state': 'Gujarat', 'full': 'Veraval, Gujarat'},
  {'city': 'Halol', 'state': 'Gujarat', 'full': 'Halol, Gujarat'},
  {'city': 'Dholera', 'state': 'Gujarat', 'full': 'Dholera, Gujarat'},
  {'city': 'Mandvi', 'state': 'Gujarat', 'full': 'Mandvi, Gujarat'},
  {'city': 'Silvassa', 'state': 'Dadra & NH', 'full': 'Silvassa, Dadra & NH'},
  {'city': 'Mumbai', 'state': 'Maharashtra', 'full': 'Mumbai, Maharashtra'},
  {'city': 'Pune', 'state': 'Maharashtra', 'full': 'Pune, Maharashtra'},
  {'city': 'Nagpur', 'state': 'Maharashtra', 'full': 'Nagpur, Maharashtra'},
  {'city': 'Nashik', 'state': 'Maharashtra', 'full': 'Nashik, Maharashtra'},
  {
    'city': 'Aurangabad',
    'state': 'Maharashtra',
    'full': 'Aurangabad, Maharashtra'
  },
  {'city': 'JNPT', 'state': 'Maharashtra', 'full': 'JNPT, Maharashtra'},
  {'city': 'Bhiwandi', 'state': 'Maharashtra', 'full': 'Bhiwandi, Maharashtra'},
  {
    'city': 'Navi Mumbai',
    'state': 'Maharashtra',
    'full': 'Navi Mumbai, Maharashtra'
  },
  {'city': 'Solapur', 'state': 'Maharashtra', 'full': 'Solapur, Maharashtra'},
  {'city': 'Kolhapur', 'state': 'Maharashtra', 'full': 'Kolhapur, Maharashtra'},
  {'city': 'Thane', 'state': 'Maharashtra', 'full': 'Thane, Maharashtra'},
  {'city': 'Raigad', 'state': 'Maharashtra', 'full': 'Raigad, Maharashtra'},
  {
    'city': 'Ahmednagar',
    'state': 'Maharashtra',
    'full': 'Ahmednagar, Maharashtra'
  },
  {'city': 'Latur', 'state': 'Maharashtra', 'full': 'Latur, Maharashtra'},
  {'city': 'Jalgaon', 'state': 'Maharashtra', 'full': 'Jalgaon, Maharashtra'},
  {'city': 'Akola', 'state': 'Maharashtra', 'full': 'Akola, Maharashtra'},
  {'city': 'Amravati', 'state': 'Maharashtra', 'full': 'Amravati, Maharashtra'},
  {'city': 'Nanded', 'state': 'Maharashtra', 'full': 'Nanded, Maharashtra'},
  {'city': 'Sangli', 'state': 'Maharashtra', 'full': 'Sangli, Maharashtra'},
  {'city': 'Satara', 'state': 'Maharashtra', 'full': 'Satara, Maharashtra'},
  {'city': 'Wardha', 'state': 'Maharashtra', 'full': 'Wardha, Maharashtra'},
  {
    'city': 'Chandrapur',
    'state': 'Maharashtra',
    'full': 'Chandrapur, Maharashtra'
  },
  {'city': 'Dhule', 'state': 'Maharashtra', 'full': 'Dhule, Maharashtra'},
  {
    'city': 'Taloja MIDC',
    'state': 'Maharashtra',
    'full': 'Taloja MIDC, Maharashtra'
  },
  {
    'city': 'Tarapur MIDC',
    'state': 'Maharashtra',
    'full': 'Tarapur MIDC, Maharashtra'
  },
  {'city': 'Delhi', 'state': 'Delhi', 'full': 'Delhi, Delhi'},
  {'city': 'New Delhi', 'state': 'Delhi', 'full': 'New Delhi, Delhi'},
  {'city': 'Noida', 'state': 'Uttar Pradesh', 'full': 'Noida, Uttar Pradesh'},
  {'city': 'Gurgaon', 'state': 'Haryana', 'full': 'Gurgaon, Haryana'},
  {'city': 'Faridabad', 'state': 'Haryana', 'full': 'Faridabad, Haryana'},
  {
    'city': 'Ghaziabad',
    'state': 'Uttar Pradesh',
    'full': 'Ghaziabad, Uttar Pradesh'
  },
  {
    'city': 'Greater Noida',
    'state': 'Uttar Pradesh',
    'full': 'Greater Noida, Uttar Pradesh'
  },
  {'city': 'Manesar', 'state': 'Haryana', 'full': 'Manesar, Haryana'},
  {'city': 'Bahadurgarh', 'state': 'Haryana', 'full': 'Bahadurgarh, Haryana'},
  {'city': 'Palwal', 'state': 'Haryana', 'full': 'Palwal, Haryana'},
  {'city': 'Jaipur', 'state': 'Rajasthan', 'full': 'Jaipur, Rajasthan'},
  {'city': 'Jodhpur', 'state': 'Rajasthan', 'full': 'Jodhpur, Rajasthan'},
  {'city': 'Udaipur', 'state': 'Rajasthan', 'full': 'Udaipur, Rajasthan'},
  {'city': 'Kota', 'state': 'Rajasthan', 'full': 'Kota, Rajasthan'},
  {'city': 'Ajmer', 'state': 'Rajasthan', 'full': 'Ajmer, Rajasthan'},
  {'city': 'Bikaner', 'state': 'Rajasthan', 'full': 'Bikaner, Rajasthan'},
  {'city': 'Alwar', 'state': 'Rajasthan', 'full': 'Alwar, Rajasthan'},
  {'city': 'Bhilwara', 'state': 'Rajasthan', 'full': 'Bhilwara, Rajasthan'},
  {'city': 'Sikar', 'state': 'Rajasthan', 'full': 'Sikar, Rajasthan'},
  {
    'city': 'Sriganganagar',
    'state': 'Rajasthan',
    'full': 'Sriganganagar, Rajasthan'
  },
  {'city': 'Barmer', 'state': 'Rajasthan', 'full': 'Barmer, Rajasthan'},
  {'city': 'Jaisalmer', 'state': 'Rajasthan', 'full': 'Jaisalmer, Rajasthan'},
  {'city': 'Pali', 'state': 'Rajasthan', 'full': 'Pali, Rajasthan'},
  {'city': 'Nagaur', 'state': 'Rajasthan', 'full': 'Nagaur, Rajasthan'},
  {'city': 'Bhiwadi', 'state': 'Rajasthan', 'full': 'Bhiwadi, Rajasthan'},
  {'city': 'Neemrana', 'state': 'Rajasthan', 'full': 'Neemrana, Rajasthan'},
  {
    'city': 'Chittorgarh',
    'state': 'Rajasthan',
    'full': 'Chittorgarh, Rajasthan'
  },
  {'city': 'Bundi', 'state': 'Rajasthan', 'full': 'Bundi, Rajasthan'},
  {'city': 'Amritsar', 'state': 'Punjab', 'full': 'Amritsar, Punjab'},
  {'city': 'Ludhiana', 'state': 'Punjab', 'full': 'Ludhiana, Punjab'},
  {'city': 'Chandigarh', 'state': 'Punjab', 'full': 'Chandigarh, Punjab'},
  {'city': 'Jalandhar', 'state': 'Punjab', 'full': 'Jalandhar, Punjab'},
  {'city': 'Patiala', 'state': 'Punjab', 'full': 'Patiala, Punjab'},
  {'city': 'Bathinda', 'state': 'Punjab', 'full': 'Bathinda, Punjab'},
  {'city': 'Mohali', 'state': 'Punjab', 'full': 'Mohali, Punjab'},
  {'city': 'Moga', 'state': 'Punjab', 'full': 'Moga, Punjab'},
  {'city': 'Pathankot', 'state': 'Punjab', 'full': 'Pathankot, Punjab'},
  {'city': 'Hoshiarpur', 'state': 'Punjab', 'full': 'Hoshiarpur, Punjab'},
  {'city': 'Phagwara', 'state': 'Punjab', 'full': 'Phagwara, Punjab'},
  {'city': 'Ropar', 'state': 'Punjab', 'full': 'Ropar, Punjab'},
  {'city': 'Panipat', 'state': 'Haryana', 'full': 'Panipat, Haryana'},
  {'city': 'Hisar', 'state': 'Haryana', 'full': 'Hisar, Haryana'},
  {'city': 'Ambala', 'state': 'Haryana', 'full': 'Ambala, Haryana'},
  {'city': 'Karnal', 'state': 'Haryana', 'full': 'Karnal, Haryana'},
  {'city': 'Rohtak', 'state': 'Haryana', 'full': 'Rohtak, Haryana'},
  {'city': 'Sonipat', 'state': 'Haryana', 'full': 'Sonipat, Haryana'},
  {'city': 'Rewari', 'state': 'Haryana', 'full': 'Rewari, Haryana'},
  {'city': 'Jhajjar', 'state': 'Haryana', 'full': 'Jhajjar, Haryana'},
  {'city': 'Sirsa', 'state': 'Haryana', 'full': 'Sirsa, Haryana'},
  {'city': 'Bhiwani', 'state': 'Haryana', 'full': 'Bhiwani, Haryana'},
  {'city': 'Yamunanagar', 'state': 'Haryana', 'full': 'Yamunanagar, Haryana'},
  {'city': 'Kurukshetra', 'state': 'Haryana', 'full': 'Kurukshetra, Haryana'},
  {
    'city': 'Lucknow',
    'state': 'Uttar Pradesh',
    'full': 'Lucknow, Uttar Pradesh'
  },
  {'city': 'Kanpur', 'state': 'Uttar Pradesh', 'full': 'Kanpur, Uttar Pradesh'},
  {'city': 'Agra', 'state': 'Uttar Pradesh', 'full': 'Agra, Uttar Pradesh'},
  {
    'city': 'Varanasi',
    'state': 'Uttar Pradesh',
    'full': 'Varanasi, Uttar Pradesh'
  },
  {'city': 'Meerut', 'state': 'Uttar Pradesh', 'full': 'Meerut, Uttar Pradesh'},
  {
    'city': 'Mathura',
    'state': 'Uttar Pradesh',
    'full': 'Mathura, Uttar Pradesh'
  },
  {
    'city': 'Allahabad',
    'state': 'Uttar Pradesh',
    'full': 'Allahabad, Uttar Pradesh'
  },
  {
    'city': 'Bareilly',
    'state': 'Uttar Pradesh',
    'full': 'Bareilly, Uttar Pradesh'
  },
  {
    'city': 'Aligarh',
    'state': 'Uttar Pradesh',
    'full': 'Aligarh, Uttar Pradesh'
  },
  {
    'city': 'Moradabad',
    'state': 'Uttar Pradesh',
    'full': 'Moradabad, Uttar Pradesh'
  },
  {
    'city': 'Gorakhpur',
    'state': 'Uttar Pradesh',
    'full': 'Gorakhpur, Uttar Pradesh'
  },
  {
    'city': 'Firozabad',
    'state': 'Uttar Pradesh',
    'full': 'Firozabad, Uttar Pradesh'
  },
  {'city': 'Jhansi', 'state': 'Uttar Pradesh', 'full': 'Jhansi, Uttar Pradesh'},
  {
    'city': 'Saharanpur',
    'state': 'Uttar Pradesh',
    'full': 'Saharanpur, Uttar Pradesh'
  },
  {
    'city': 'Muzaffarnagar',
    'state': 'Uttar Pradesh',
    'full': 'Muzaffarnagar, Uttar Pradesh'
  },
  {'city': 'Hapur', 'state': 'Uttar Pradesh', 'full': 'Hapur, Uttar Pradesh'},
  {'city': 'Unnao', 'state': 'Uttar Pradesh', 'full': 'Unnao, Uttar Pradesh'},
  {
    'city': 'Bulandshahr',
    'state': 'Uttar Pradesh',
    'full': 'Bulandshahr, Uttar Pradesh'
  },
  {
    'city': 'Bhopal',
    'state': 'Madhya Pradesh',
    'full': 'Bhopal, Madhya Pradesh'
  },
  {
    'city': 'Indore',
    'state': 'Madhya Pradesh',
    'full': 'Indore, Madhya Pradesh'
  },
  {
    'city': 'Jabalpur',
    'state': 'Madhya Pradesh',
    'full': 'Jabalpur, Madhya Pradesh'
  },
  {
    'city': 'Ratlam',
    'state': 'Madhya Pradesh',
    'full': 'Ratlam, Madhya Pradesh'
  },
  {'city': 'Dewas', 'state': 'Madhya Pradesh', 'full': 'Dewas, Madhya Pradesh'},
  {
    'city': 'Gwalior',
    'state': 'Madhya Pradesh',
    'full': 'Gwalior, Madhya Pradesh'
  },
  {
    'city': 'Ujjain',
    'state': 'Madhya Pradesh',
    'full': 'Ujjain, Madhya Pradesh'
  },
  {'city': 'Sagar', 'state': 'Madhya Pradesh', 'full': 'Sagar, Madhya Pradesh'},
  {'city': 'Satna', 'state': 'Madhya Pradesh', 'full': 'Satna, Madhya Pradesh'},
  {'city': 'Katni', 'state': 'Madhya Pradesh', 'full': 'Katni, Madhya Pradesh'},
  {
    'city': 'Chhindwara',
    'state': 'Madhya Pradesh',
    'full': 'Chhindwara, Madhya Pradesh'
  },
  {
    'city': 'Pithampur',
    'state': 'Madhya Pradesh',
    'full': 'Pithampur, Madhya Pradesh'
  },
  {
    'city': 'Mandideep',
    'state': 'Madhya Pradesh',
    'full': 'Mandideep, Madhya Pradesh'
  },
  {
    'city': 'Khandwa',
    'state': 'Madhya Pradesh',
    'full': 'Khandwa, Madhya Pradesh'
  },
  {'city': 'Rewa', 'state': 'Madhya Pradesh', 'full': 'Rewa, Madhya Pradesh'},
  {'city': 'Hyderabad', 'state': 'Telangana', 'full': 'Hyderabad, Telangana'},
  {'city': 'Warangal', 'state': 'Telangana', 'full': 'Warangal, Telangana'},
  {'city': 'Karimnagar', 'state': 'Telangana', 'full': 'Karimnagar, Telangana'},
  {'city': 'Nizamabad', 'state': 'Telangana', 'full': 'Nizamabad, Telangana'},
  {'city': 'Khammam', 'state': 'Telangana', 'full': 'Khammam, Telangana'},
  {
    'city': 'Secunderabad',
    'state': 'Telangana',
    'full': 'Secunderabad, Telangana'
  },
  {'city': 'Sangareddy', 'state': 'Telangana', 'full': 'Sangareddy, Telangana'},
  {'city': 'Mancherial', 'state': 'Telangana', 'full': 'Mancherial, Telangana'},
  {
    'city': 'Visakhapatnam',
    'state': 'Andhra Pradesh',
    'full': 'Visakhapatnam, Andhra Pradesh'
  },
  {
    'city': 'Vijayawada',
    'state': 'Andhra Pradesh',
    'full': 'Vijayawada, Andhra Pradesh'
  },
  {
    'city': 'Guntur',
    'state': 'Andhra Pradesh',
    'full': 'Guntur, Andhra Pradesh'
  },
  {
    'city': 'Kakinada',
    'state': 'Andhra Pradesh',
    'full': 'Kakinada, Andhra Pradesh'
  },
  {
    'city': 'Nellore',
    'state': 'Andhra Pradesh',
    'full': 'Nellore, Andhra Pradesh'
  },
  {
    'city': 'Tirupati',
    'state': 'Andhra Pradesh',
    'full': 'Tirupati, Andhra Pradesh'
  },
  {
    'city': 'Kurnool',
    'state': 'Andhra Pradesh',
    'full': 'Kurnool, Andhra Pradesh'
  },
  {
    'city': 'Rajahmundry',
    'state': 'Andhra Pradesh',
    'full': 'Rajahmundry, Andhra Pradesh'
  },
  {
    'city': 'Anantapur',
    'state': 'Andhra Pradesh',
    'full': 'Anantapur, Andhra Pradesh'
  },
  {
    'city': 'Ongole',
    'state': 'Andhra Pradesh',
    'full': 'Ongole, Andhra Pradesh'
  },
  {
    'city': 'Vizianagaram',
    'state': 'Andhra Pradesh',
    'full': 'Vizianagaram, Andhra Pradesh'
  },
  {'city': 'Eluru', 'state': 'Andhra Pradesh', 'full': 'Eluru, Andhra Pradesh'},
  {'city': 'Bangalore', 'state': 'Karnataka', 'full': 'Bangalore, Karnataka'},
  {'city': 'Mysuru', 'state': 'Karnataka', 'full': 'Mysuru, Karnataka'},
  {'city': 'Mangaluru', 'state': 'Karnataka', 'full': 'Mangaluru, Karnataka'},
  {'city': 'Hubli', 'state': 'Karnataka', 'full': 'Hubli, Karnataka'},
  {'city': 'Belgaum', 'state': 'Karnataka', 'full': 'Belgaum, Karnataka'},
  {'city': 'Davangere', 'state': 'Karnataka', 'full': 'Davangere, Karnataka'},
  {'city': 'Ballari', 'state': 'Karnataka', 'full': 'Ballari, Karnataka'},
  {'city': 'Tumkur', 'state': 'Karnataka', 'full': 'Tumkur, Karnataka'},
  {'city': 'Gulbarga', 'state': 'Karnataka', 'full': 'Gulbarga, Karnataka'},
  {'city': 'Raichur', 'state': 'Karnataka', 'full': 'Raichur, Karnataka'},
  {'city': 'Udupi', 'state': 'Karnataka', 'full': 'Udupi, Karnataka'},
  {'city': 'Bidar', 'state': 'Karnataka', 'full': 'Bidar, Karnataka'},
  {'city': 'Shimoga', 'state': 'Karnataka', 'full': 'Shimoga, Karnataka'},
  {'city': 'Hassan', 'state': 'Karnataka', 'full': 'Hassan, Karnataka'},
  {
    'city': 'Chikmagalur',
    'state': 'Karnataka',
    'full': 'Chikmagalur, Karnataka'
  },
  {'city': 'Chennai', 'state': 'Tamil Nadu', 'full': 'Chennai, Tamil Nadu'},
  {
    'city': 'Coimbatore',
    'state': 'Tamil Nadu',
    'full': 'Coimbatore, Tamil Nadu'
  },
  {'city': 'Madurai', 'state': 'Tamil Nadu', 'full': 'Madurai, Tamil Nadu'},
  {
    'city': 'Thoothukudi',
    'state': 'Tamil Nadu',
    'full': 'Thoothukudi, Tamil Nadu'
  },
  {
    'city': 'Tiruchirappalli',
    'state': 'Tamil Nadu',
    'full': 'Tiruchirappalli, Tamil Nadu'
  },
  {'city': 'Salem', 'state': 'Tamil Nadu', 'full': 'Salem, Tamil Nadu'},
  {
    'city': 'Tirunelveli',
    'state': 'Tamil Nadu',
    'full': 'Tirunelveli, Tamil Nadu'
  },
  {'city': 'Tiruppur', 'state': 'Tamil Nadu', 'full': 'Tiruppur, Tamil Nadu'},
  {'city': 'Vellore', 'state': 'Tamil Nadu', 'full': 'Vellore, Tamil Nadu'},
  {'city': 'Erode', 'state': 'Tamil Nadu', 'full': 'Erode, Tamil Nadu'},
  {'city': 'Hosur', 'state': 'Tamil Nadu', 'full': 'Hosur, Tamil Nadu'},
  {'city': 'Cuddalore', 'state': 'Tamil Nadu', 'full': 'Cuddalore, Tamil Nadu'},
  {
    'city': 'Ennore Port',
    'state': 'Tamil Nadu',
    'full': 'Ennore Port, Tamil Nadu'
  },
  {
    'city': 'Kamarajar Port',
    'state': 'Tamil Nadu',
    'full': 'Kamarajar Port, Tamil Nadu'
  },
  {'city': 'Nagercoil', 'state': 'Tamil Nadu', 'full': 'Nagercoil, Tamil Nadu'},
  {'city': 'Kochi', 'state': 'Kerala', 'full': 'Kochi, Kerala'},
  {
    'city': 'Thiruvananthapuram',
    'state': 'Kerala',
    'full': 'Thiruvananthapuram, Kerala'
  },
  {'city': 'Kozhikode', 'state': 'Kerala', 'full': 'Kozhikode, Kerala'},
  {'city': 'Thrissur', 'state': 'Kerala', 'full': 'Thrissur, Kerala'},
  {'city': 'Kollam', 'state': 'Kerala', 'full': 'Kollam, Kerala'},
  {'city': 'Kannur', 'state': 'Kerala', 'full': 'Kannur, Kerala'},
  {'city': 'Alappuzha', 'state': 'Kerala', 'full': 'Alappuzha, Kerala'},
  {'city': 'Palakkad', 'state': 'Kerala', 'full': 'Palakkad, Kerala'},
  {'city': 'Malappuram', 'state': 'Kerala', 'full': 'Malappuram, Kerala'},
  {'city': 'Kottayam', 'state': 'Kerala', 'full': 'Kottayam, Kerala'},
  {'city': 'Kasaragod', 'state': 'Kerala', 'full': 'Kasaragod, Kerala'},
  {'city': 'Kolkata', 'state': 'West Bengal', 'full': 'Kolkata, West Bengal'},
  {
    'city': 'Haldia Port',
    'state': 'West Bengal',
    'full': 'Haldia Port, West Bengal'
  },
  {'city': 'Howrah', 'state': 'West Bengal', 'full': 'Howrah, West Bengal'},
  {'city': 'Durgapur', 'state': 'West Bengal', 'full': 'Durgapur, West Bengal'},
  {'city': 'Asansol', 'state': 'West Bengal', 'full': 'Asansol, West Bengal'},
  {'city': 'Siliguri', 'state': 'West Bengal', 'full': 'Siliguri, West Bengal'},
  {
    'city': 'Kharagpur',
    'state': 'West Bengal',
    'full': 'Kharagpur, West Bengal'
  },
  {
    'city': 'Bardhaman',
    'state': 'West Bengal',
    'full': 'Bardhaman, West Bengal'
  },
  {'city': 'Malda', 'state': 'West Bengal', 'full': 'Malda, West Bengal'},
  {'city': 'Bhubaneswar', 'state': 'Odisha', 'full': 'Bhubaneswar, Odisha'},
  {'city': 'Paradip', 'state': 'Odisha', 'full': 'Paradip, Odisha'},
  {'city': 'Cuttack', 'state': 'Odisha', 'full': 'Cuttack, Odisha'},
  {'city': 'Rourkela', 'state': 'Odisha', 'full': 'Rourkela, Odisha'},
  {'city': 'Berhampur', 'state': 'Odisha', 'full': 'Berhampur, Odisha'},
  {'city': 'Sambalpur', 'state': 'Odisha', 'full': 'Sambalpur, Odisha'},
  {'city': 'Jharsuguda', 'state': 'Odisha', 'full': 'Jharsuguda, Odisha'},
  {'city': 'Angul', 'state': 'Odisha', 'full': 'Angul, Odisha'},
  {'city': 'Talcher', 'state': 'Odisha', 'full': 'Talcher, Odisha'},
  {'city': 'Dhamra Port', 'state': 'Odisha', 'full': 'Dhamra Port, Odisha'},
  {'city': 'Patna', 'state': 'Bihar', 'full': 'Patna, Bihar'},
  {'city': 'Muzaffarpur', 'state': 'Bihar', 'full': 'Muzaffarpur, Bihar'},
  {'city': 'Gaya', 'state': 'Bihar', 'full': 'Gaya, Bihar'},
  {'city': 'Bhagalpur', 'state': 'Bihar', 'full': 'Bhagalpur, Bihar'},
  {'city': 'Purnia', 'state': 'Bihar', 'full': 'Purnia, Bihar'},
  {'city': 'Darbhanga', 'state': 'Bihar', 'full': 'Darbhanga, Bihar'},
  {'city': 'Hajipur', 'state': 'Bihar', 'full': 'Hajipur, Bihar'},
  {'city': 'Arrah', 'state': 'Bihar', 'full': 'Arrah, Bihar'},
  {'city': 'Ranchi', 'state': 'Jharkhand', 'full': 'Ranchi, Jharkhand'},
  {'city': 'Jamshedpur', 'state': 'Jharkhand', 'full': 'Jamshedpur, Jharkhand'},
  {'city': 'Dhanbad', 'state': 'Jharkhand', 'full': 'Dhanbad, Jharkhand'},
  {'city': 'Bokaro', 'state': 'Jharkhand', 'full': 'Bokaro, Jharkhand'},
  {'city': 'Hazaribagh', 'state': 'Jharkhand', 'full': 'Hazaribagh, Jharkhand'},
  {'city': 'Deoghar', 'state': 'Jharkhand', 'full': 'Deoghar, Jharkhand'},
  {'city': 'Giridih', 'state': 'Jharkhand', 'full': 'Giridih, Jharkhand'},
  {'city': 'Raipur', 'state': 'Chhattisgarh', 'full': 'Raipur, Chhattisgarh'},
  {'city': 'Bhilai', 'state': 'Chhattisgarh', 'full': 'Bhilai, Chhattisgarh'},
  {
    'city': 'Bilaspur',
    'state': 'Chhattisgarh',
    'full': 'Bilaspur, Chhattisgarh'
  },
  {'city': 'Durg', 'state': 'Chhattisgarh', 'full': 'Durg, Chhattisgarh'},
  {'city': 'Korba', 'state': 'Chhattisgarh', 'full': 'Korba, Chhattisgarh'},
  {'city': 'Raigarh', 'state': 'Chhattisgarh', 'full': 'Raigarh, Chhattisgarh'},
  {
    'city': 'Jagdalpur',
    'state': 'Chhattisgarh',
    'full': 'Jagdalpur, Chhattisgarh'
  },
  {'city': 'Guwahati', 'state': 'Assam', 'full': 'Guwahati, Assam'},
  {'city': 'Dibrugarh', 'state': 'Assam', 'full': 'Dibrugarh, Assam'},
  {'city': 'Jorhat', 'state': 'Assam', 'full': 'Jorhat, Assam'},
  {'city': 'Silchar', 'state': 'Assam', 'full': 'Silchar, Assam'},
  {'city': 'Tezpur', 'state': 'Assam', 'full': 'Tezpur, Assam'},
  {'city': 'Nagaon', 'state': 'Assam', 'full': 'Nagaon, Assam'},
  {'city': 'Bongaigaon', 'state': 'Assam', 'full': 'Bongaigaon, Assam'},
  {'city': 'Numaligarh', 'state': 'Assam', 'full': 'Numaligarh, Assam'},
  {'city': 'Dehradun', 'state': 'Uttarakhand', 'full': 'Dehradun, Uttarakhand'},
  {'city': 'Haridwar', 'state': 'Uttarakhand', 'full': 'Haridwar, Uttarakhand'},
  {'city': 'Roorkee', 'state': 'Uttarakhand', 'full': 'Roorkee, Uttarakhand'},
  {'city': 'Haldwani', 'state': 'Uttarakhand', 'full': 'Haldwani, Uttarakhand'},
  {'city': 'Rudrapur', 'state': 'Uttarakhand', 'full': 'Rudrapur, Uttarakhand'},
  {
    'city': 'Rishikesh',
    'state': 'Uttarakhand',
    'full': 'Rishikesh, Uttarakhand'
  },
  {'city': 'Kashipur', 'state': 'Uttarakhand', 'full': 'Kashipur, Uttarakhand'},
  {
    'city': 'Pantnagar',
    'state': 'Uttarakhand',
    'full': 'Pantnagar, Uttarakhand'
  },
  {
    'city': 'Shimla',
    'state': 'Himachal Pradesh',
    'full': 'Shimla, Himachal Pradesh'
  },
  {
    'city': 'Manali',
    'state': 'Himachal Pradesh',
    'full': 'Manali, Himachal Pradesh'
  },
  {
    'city': 'Solan',
    'state': 'Himachal Pradesh',
    'full': 'Solan, Himachal Pradesh'
  },
  {
    'city': 'Baddi',
    'state': 'Himachal Pradesh',
    'full': 'Baddi, Himachal Pradesh'
  },
  {
    'city': 'Paonta Sahib',
    'state': 'Himachal Pradesh',
    'full': 'Paonta Sahib, Himachal Pradesh'
  },
  {
    'city': 'Dharamsala',
    'state': 'Himachal Pradesh',
    'full': 'Dharamsala, Himachal Pradesh'
  },
  {
    'city': 'Mandi',
    'state': 'Himachal Pradesh',
    'full': 'Mandi, Himachal Pradesh'
  },
  {'city': 'Panaji', 'state': 'Goa', 'full': 'Panaji, Goa'},
  {'city': 'Vasco da Gama', 'state': 'Goa', 'full': 'Vasco da Gama, Goa'},
  {'city': 'Margao', 'state': 'Goa', 'full': 'Margao, Goa'},
  {'city': 'Mormugao Port', 'state': 'Goa', 'full': 'Mormugao Port, Goa'},
  {'city': 'Jammu', 'state': 'J&K', 'full': 'Jammu, J&K'},
  {'city': 'Srinagar', 'state': 'J&K', 'full': 'Srinagar, J&K'},
  {'city': 'Kathua', 'state': 'J&K', 'full': 'Kathua, J&K'},
  {'city': 'Udhampur', 'state': 'J&K', 'full': 'Udhampur, J&K'},
  {'city': 'Leh', 'state': 'Ladakh', 'full': 'Leh, Ladakh'},
  {'city': 'Imphal', 'state': 'Manipur', 'full': 'Imphal, Manipur'},
  {'city': 'Shillong', 'state': 'Meghalaya', 'full': 'Shillong, Meghalaya'},
  {'city': 'Agartala', 'state': 'Tripura', 'full': 'Agartala, Tripura'},
  {'city': 'Aizawl', 'state': 'Mizoram', 'full': 'Aizawl, Mizoram'},
  {'city': 'Kohima', 'state': 'Nagaland', 'full': 'Kohima, Nagaland'},
  {
    'city': 'Itanagar',
    'state': 'Arunachal Pradesh',
    'full': 'Itanagar, Arunachal Pradesh'
  },
  {'city': 'Gangtok', 'state': 'Sikkim', 'full': 'Gangtok, Sikkim'},
  {'city': 'Dimapur', 'state': 'Nagaland', 'full': 'Dimapur, Nagaland'},
  {'city': 'Tura', 'state': 'Meghalaya', 'full': 'Tura, Meghalaya'},
  // Union Territories
  {'city': 'Daman', 'state': 'Daman & Diu', 'full': 'Daman, Daman & Diu'},
  {'city': 'Diu', 'state': 'Daman & Diu', 'full': 'Diu, Daman & Diu'},
  {
    'city': 'Puducherry',
    'state': 'Puducherry',
    'full': 'Puducherry, Puducherry'
  },
  {'city': 'Karaikal', 'state': 'Puducherry', 'full': 'Karaikal, Puducherry'},
  {'city': 'Mahe', 'state': 'Puducherry', 'full': 'Mahe, Puducherry'},
  {'city': 'Yanam', 'state': 'Puducherry', 'full': 'Yanam, Puducherry'},
  {
    'city': 'Lakshadweep',
    'state': 'Lakshadweep',
    'full': 'Kavaratti, Lakshadweep'
  },
  {
    'city': 'Port Blair',
    'state': 'Andaman & Nicobar',
    'full': 'Port Blair, Andaman & Nicobar'
  },
  {
    'city': 'Chandigarh',
    'state': 'Chandigarh',
    'full': 'Chandigarh UT, Chandigarh'
  },
  // Additional industrial cities
  {
    'city': 'Ludhiana Industrial Area',
    'state': 'Punjab',
    'full': 'Ludhiana Industrial Area, Punjab'
  },
  {
    'city': 'Manali Refinery',
    'state': 'Tamil Nadu',
    'full': 'Manali Refinery, Tamil Nadu'
  },
  {'city': 'Dahej SEZ', 'state': 'Gujarat', 'full': 'Dahej SEZ, Gujarat'},
  {'city': 'Hajira', 'state': 'Gujarat', 'full': 'Hajira, Gujarat'},
  {'city': 'Savli', 'state': 'Gujarat', 'full': 'Savli, Gujarat'},
  {'city': 'Padra', 'state': 'Gujarat', 'full': 'Padra, Gujarat'},
  {'city': 'Kalol', 'state': 'Gujarat', 'full': 'Kalol, Gujarat'},
  {'city': 'Kadi', 'state': 'Gujarat', 'full': 'Kadi, Gujarat'},
  {'city': 'Vatva GIDC', 'state': 'Gujarat', 'full': 'Vatva GIDC, Gujarat'},
  {'city': 'Naroda GIDC', 'state': 'Gujarat', 'full': 'Naroda GIDC, Gujarat'},
  {'city': 'Odhav GIDC', 'state': 'Gujarat', 'full': 'Odhav GIDC, Gujarat'},
  {'city': 'Panoli GIDC', 'state': 'Gujarat', 'full': 'Panoli GIDC, Gujarat'},
  {'city': 'Jhagadia', 'state': 'Gujarat', 'full': 'Jhagadia, Gujarat'},
  {'city': 'Sachin GIDC', 'state': 'Gujarat', 'full': 'Sachin GIDC, Gujarat'},
];

// NHAI FY2024-25 FASTag toll rates â€” â‚¹ per km (national highway average)
// Source: NHAI fee notification, avg across major NH corridors
// Rates calibrated: Bathinda-Daman ~1440km x â‚¹8.1/km = â‚¹11,664 âœ“
const Map<int, double> kTollPerAxlePerKm = {
  2: 2.30, // 2-axle LCV / mini truck
  3: 4.60, // 3-axle medium truck
  4: 5.50, // 4-axle heavy truck / bus
  5: 7.20, // 5-axle MAV
  6: 8.10, // 6-axle tanker (most SS/MS tankers) â€” e.g. 1440kmÃ—8.1=â‚¹11,664
  7: 9.40, // 7-axle oversize
  8: 10.80, // 8-axle heavy special vehicle
};

// ================================================================
// MODELS
// ================================================================

class BankEntry {
  final String date, narration, refNo;
  final double debit, credit;
  bool isMatched;
  String? matchedLedgerId;
  BankEntry(
      {required this.date,
      required this.narration,
      required this.refNo,
      required this.debit,
      required this.credit,
      this.isMatched = false,
      this.matchedLedgerId});
}

class Battery {
  String make, model, serialNo, billNo, purchaseDate, warrantyExpiry;
  double warrantyYears;
  Battery(
      {required this.make,
      this.model = '',
      required this.serialNo,
      this.billNo = '',
      required this.purchaseDate,
      required this.warrantyExpiry,
      this.warrantyYears = 1.0});
  Map<String, dynamic> toJson() => {
        'make': make,
        'model': model,
        'serialNo': serialNo,
        'billNo': billNo,
        'purchaseDate': purchaseDate,
        'warrantyExpiry': warrantyExpiry,
        'warrantyYears': warrantyYears
      };
  factory Battery.fromJson(Map<String, dynamic> j) => Battery(
      make: j['make'] ?? '',
      model: j['model'] ?? '',
      serialNo: j['serialNo'] ?? '',
      billNo: j['billNo'] ?? '',
      purchaseDate: j['purchaseDate'] ?? '',
      warrantyExpiry: j['warrantyExpiry'] ?? '',
      warrantyYears: (j['warrantyYears'] as num?)?.toDouble() ?? 1.0);
}

class DriverDoc {
  String type; // aadhaar, dl, photo
  bool isUploaded;
  String fileName, uploadDate, docNumber, expiryDate, filePath, mimeType;
  DriverDoc(
      {required this.type,
      this.isUploaded = false,
      this.fileName = '',
      this.uploadDate = '',
      this.docNumber = '',
      this.expiryDate = '',
      this.filePath = '',
      this.mimeType = ''});
  String get label {
    switch (type) {
      case 'aadhaar':
        return 'Aadhaar Card';
      case 'dl':
        return 'Driving Licence';
      case 'photo':
        return 'Driver Photo';
      default:
        return type;
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'isUploaded': isUploaded,
        'fileName': fileName,
        'uploadDate': uploadDate,
        'docNumber': docNumber,
        'expiryDate': expiryDate,
        'filePath': filePath,
        'mimeType': mimeType
      };
  factory DriverDoc.fromJson(Map<String, dynamic> j) => DriverDoc(
      type: j['type'] ?? '',
      isUploaded: j['isUploaded'] ?? false,
      fileName: j['fileName'] ?? '',
      uploadDate: j['uploadDate'] ?? '',
      docNumber: j['docNumber'] ?? '',
      expiryDate: j['expiryDate'] ?? '',
      filePath: j['filePath'] ?? '',
      mimeType: j['mimeType'] ?? '');
}

class SubscriptionInfo {
  SubscriptionTier tier;
  String expiryDate;
  int tripsUsedThisMonth;
  SubscriptionInfo(
      {this.tier = SubscriptionTier.free,
      this.expiryDate = "",
      this.tripsUsedThisMonth = 0});
  bool get canUseGPS => tier != SubscriptionTier.free;
  bool get canUseKredX =>
      tier == SubscriptionTier.business || tier == SubscriptionTier.enterprise;
  bool get canExportPDF => tier != SubscriptionTier.free;
  bool get isEnterprise => tier == SubscriptionTier.enterprise;
  int get maxUsers => tier == SubscriptionTier.enterprise
      ? 10
      : tier == SubscriptionTier.business
          ? 3
          : 1;
  int get maxVehicles => tier == SubscriptionTier.enterprise
      ? 999
      : tier == SubscriptionTier.business
          ? 50
          : tier == SubscriptionTier.pro
              ? 15
              : 5;
  bool get isTripsLimitReached =>
      tier == SubscriptionTier.free && tripsUsedThisMonth >= 10;
  String get tierName {
    switch (tier) {
      case SubscriptionTier.free:
        return "FREE";
      case SubscriptionTier.pro:
        return "PRO";
      case SubscriptionTier.business:
        return "BUSINESS";
      case SubscriptionTier.enterprise:
        return "ENTERPRISE";
    }
    return "FREE";
  }

  Color get tierColor {
    switch (tier) {
      case SubscriptionTier.free:
        return Colors.grey;
      case SubscriptionTier.pro:
        return Colors.blueAccent;
      case SubscriptionTier.business:
        return Colors.amber.shade700;
      case SubscriptionTier.enterprise:
        return const Color(0xFFFB8C00);
    }
    return Colors.grey;
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.index,
        'expiryDate': expiryDate,
        'tripsUsedThisMonth': tripsUsedThisMonth
      };
  factory SubscriptionInfo.fromJson(Map<String, dynamic> j) => SubscriptionInfo(
      tier: SubscriptionTier.values[j['tier'] ?? 0],
      expiryDate: j['expiryDate'] ?? "",
      tripsUsedThisMonth: j['tripsUsedThisMonth'] ?? 0);
}

class KredXApplication {
  String id, invoiceLedgerId, partyName;
  double invoiceAmount, requestedAmount, approvedAmount;
  KredXStatus status;
  String appliedDate;
  int tenureDays;
  double interestRate;
  KredXApplication(
      {required this.id,
      required this.invoiceLedgerId,
      required this.partyName,
      required this.invoiceAmount,
      required this.requestedAmount,
      this.approvedAmount = 0,
      this.status = KredXStatus.draft,
      required this.appliedDate,
      this.tenureDays = 30,
      this.interestRate = 1.5});
  double get estimatedInterest =>
      (approvedAmount > 0 ? approvedAmount : requestedAmount) *
      (interestRate / 100) *
      (tenureDays / 30);
  double get netDisbursal =>
      (approvedAmount > 0 ? approvedAmount : requestedAmount) -
      estimatedInterest;
  String get statusLabel {
    switch (status) {
      case KredXStatus.draft:
        return "Draft";
      case KredXStatus.submitted:
        return "Submitted";
      case KredXStatus.underReview:
        return "Under Review";
      case KredXStatus.approved:
        return "Approved";
      case KredXStatus.disbursed:
        return "Disbursed";
      case KredXStatus.rejected:
        return "Rejected";
    }
    return "Draft";
  }

  Color get statusColor {
    switch (status) {
      case KredXStatus.draft:
        return Colors.grey;
      case KredXStatus.submitted:
        return Colors.blue;
      case KredXStatus.underReview:
        return Colors.orange;
      case KredXStatus.approved:
        return Colors.green;
      case KredXStatus.disbursed:
        return Colors.teal;
      case KredXStatus.rejected:
        return Colors.red;
    }
    return Colors.grey;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoiceLedgerId': invoiceLedgerId,
        'partyName': partyName,
        'invoiceAmount': invoiceAmount,
        'requestedAmount': requestedAmount,
        'approvedAmount': approvedAmount,
        'status': status.index,
        'appliedDate': appliedDate,
        'tenureDays': tenureDays,
        'interestRate': interestRate
      };
  factory KredXApplication.fromJson(Map<String, dynamic> j) => KredXApplication(
      id: j['id'],
      invoiceLedgerId: j['invoiceLedgerId'],
      partyName: j['partyName'],
      invoiceAmount: (j['invoiceAmount'] as num).toDouble(),
      requestedAmount: (j['requestedAmount'] as num).toDouble(),
      approvedAmount: (j['approvedAmount'] as num? ?? 0).toDouble(),
      status: KredXStatus.values[j['status'] ?? 0],
      appliedDate: j['appliedDate'],
      tenureDays: j['tenureDays'] ?? 30,
      interestRate: (j['interestRate'] as num? ?? 1.5).toDouble());
}

class UserProfile {
  String companyName,
      gstin,
      phone,
      address,
      email,
      bankName,
      bankAccount,
      bankIfsc,
      panNumber;
  UserProfile(
      {this.companyName = "Sandhu Logistics",
      this.gstin = "Unregistered",
      this.phone = "+91 0000000000",
      this.address = "Ahmedabad, Gujarat",
      this.email = "",
      this.bankName = "",
      this.bankAccount = "",
      this.bankIfsc = "",
      this.panNumber = ""});
  Map<String, dynamic> toJson() => {
        'companyName': companyName,
        'gstin': gstin,
        'phone': phone,
        'address': address,
        'email': email,
        'bankName': bankName,
        'bankAccount': bankAccount,
        'bankIfsc': bankIfsc,
        'panNumber': panNumber
      };
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
      companyName: j['companyName'] ?? "",
      gstin: j['gstin'] ?? "",
      phone: j['phone'] ?? "",
      address: j['address'] ?? "",
      email: j['email'] ?? "",
      bankName: j['bankName'] ?? "",
      bankAccount: j['bankAccount'] ?? "",
      bankIfsc: j['bankIfsc'] ?? "",
      panNumber: j['panNumber'] ?? "");
}

class DriverTx {
  String date;
  DriverTxType type;
  double amount;
  String note;
  DriverTx(
      {required this.date,
      required this.type,
      required this.amount,
      required this.note});
  Map<String, dynamic> toJson() =>
      {'date': date, 'type': type.index, 'amount': amount, 'note': note};
  factory DriverTx.fromJson(Map<String, dynamic> j) => DriverTx(
      date: j['date'],
      type: DriverTxType.values[j['type']],
      amount: (j['amount'] as num).toDouble(),
      note: j['note']);
}

class Driver {
  String id, name, phone, aadharNum, dlNum;
  double balance, monthlySalary;
  List<DriverTx> transactions;
  List<DriverDoc> documents;
  Driver(
      {required this.id,
      required this.name,
      required this.phone,
      required this.balance,
      required this.transactions,
      this.aadharNum = "",
      this.dlNum = "",
      this.monthlySalary = 0,
      List<DriverDoc>? documents})
      : documents = documents ??
            [
              DriverDoc(type: 'aadhaar'),
              DriverDoc(type: 'dl'),
              DriverDoc(type: 'photo')
            ];
  bool get isVerified => documents.every((d) => (d).isUploaded);
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'balance': balance,
        'aadharNum': aadharNum,
        'dlNum': dlNum,
        'monthlySalary': monthlySalary,
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'documents': documents.map((d) => (d).toJson()).toList()
      };
  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
      id: j['id'],
      name: j['name'],
      phone: j['phone'],
      balance: (j['balance'] as num).toDouble(),
      monthlySalary: (j['monthlySalary'] as num? ?? 0).toDouble(),
      transactions:
          (j['transactions'] as List).map((t) => DriverTx.fromJson(t)).toList(),
      aadharNum: j['aadharNum'] ?? "",
      dlNum: j['dlNum'] ?? "",
      documents: j['documents'] != null
          ? (j['documents'] as List).map((d) => DriverDoc.fromJson(d)).toList()
          : null);
}

// Part load invoice item â€” supports multiple products in one truck
class InvoiceItem {
  String invoiceNo;
  String materialName;
  double weight;
  String weightUnit;
  String description;
  double value; // declared value for LR

  InvoiceItem(
      {this.invoiceNo = '',
      this.materialName = '',
      this.weight = 0,
      this.weightUnit = 'MT',
      this.description = '',
      this.value = 0});

  Map<String, dynamic> toJson() => {
        'invoiceNo': invoiceNo,
        'materialName': materialName,
        'weight': weight,
        'weightUnit': weightUnit,
        'description': description,
        'value': value
      };

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
      invoiceNo: j['invoiceNo'] ?? '',
      materialName: j['materialName'] ?? '',
      weight: (j['weight'] as num? ?? 0).toDouble(),
      weightUnit: j['weightUnit'] ?? 'MT',
      description: j['description'] ?? '',
      value: (j['value'] as num? ?? 0).toDouble());
}

class TripLedger {
  String id, date, partyName, vehicleNo, route;
  VehicleOwnership ownership;
  String eWayBillNo, materialName;
  String loadingPoint, unloadingPoint, loadingState, unloadingState;
  String consignorPhone, consignorEmail, consignorGstin;
  double freightBilled, paymentReceived;
  double diesel, toll, driverExp, materialLoss;
  double marketTruckFreight, marketAdvancePaid;
  double penalties, tdsDeduction;
  double distanceKm, fuelEconomy;
  String? driverName;
  int paymentTermsDays;
  String lrNotes;
  GstType gstType;
  double gstRate;
  bool isGstInclusive;
  double weightTons;
  String weightUnit;

  List<InvoiceItem> invoiceItems; // part load items â€” multiple products
  String materialInvoiceNo; // main invoice number
  String dispatchedAt; // ISO timestamp when truck left
  String estimatedArrival; // ISO timestamp of expected arrival
  bool isInTransit;
  double platformCommission; // 2% of freight â€” platform fee from fleet owner
  double
      consignorCommission; // 2% of freight â€” platform fee from consignor (billed separately)

  TripLedger(
      {required this.id,
      required this.date,
      required this.partyName,
      required this.vehicleNo,
      required this.route,
      required this.ownership,
      this.eWayBillNo = "PENDING",
      this.materialName = "General Goods",
      this.loadingPoint = "",
      this.unloadingPoint = "",
      this.loadingState = "",
      this.unloadingState = "",
      this.consignorPhone = "",
      this.consignorEmail = "",
      this.consignorGstin = "",
      required this.freightBilled,
      this.paymentReceived = 0,
      this.diesel = 0,
      this.toll = 0,
      this.driverExp = 0,
      this.materialLoss = 0,
      this.marketTruckFreight = 0,
      this.marketAdvancePaid = 0,
      this.penalties = 0,
      this.tdsDeduction = 0,
      this.distanceKm = 0,
      this.fuelEconomy = 3.5,
      this.driverName,
      this.paymentTermsDays = 30,
      this.lrNotes = "",
      this.gstType = GstType.none,
      this.gstRate = 0,
      this.isGstInclusive = false,
      this.weightTons = 0,
      this.weightUnit = "MT",
      this.dispatchedAt = "",
      this.estimatedArrival = "",
      this.isInTransit = false,
      this.platformCommission = 0,
      this.consignorCommission = 0,
      List<InvoiceItem>? invoiceItems,
      this.materialInvoiceNo = ""})
      : invoiceItems = invoiceItems ?? [];

  double get gstAmount {
    if (gstType == GstType.none) return 0;
    return isGstInclusive
        ? freightBilled - (freightBilled / (1 + gstRate / 100))
        : freightBilled * gstRate / 100;
  }

  double get taxableFreight => isGstInclusive && gstRate > 0
      ? (freightBilled / (1 + gstRate / 100))
      : freightBilled;
  double get selfExpenses => diesel + toll + driverExp + materialLoss;
  double get platformCommissionTotal =>
      platformCommission + consignorCommission;
  double get tripProfit => ownership == VehicleOwnership.self
      ? (freightBilled -
          selfExpenses -
          penalties -
          tdsDeduction -
          platformCommission)
      : (freightBilled -
          marketTruckFreight -
          materialLoss -
          platformCommission);
  double get partyPending =>
      freightBilled - paymentReceived - tdsDeduction - penalties;

  DateTime? get paymentDueDate {
    try {
      final p = date.split('/');
      return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]))
          .add(Duration(days: paymentTermsDays));
    } catch (_) {
      return null;
    }
  }

  bool get isPaymentOverdue {
    final d = paymentDueDate;
    return d != null && partyPending > 0 && DateTime.now().isAfter(d);
  }

  bool get isDueSoon {
    final d = paymentDueDate;
    if (d == null || partyPending <= 0) return false;
    final diff = d.difference(DateTime.now()).inDays;
    return diff >= 0 && diff <= AppConfig.paymentAlertDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'partyName': partyName,
        'vehicleNo': vehicleNo,
        'route': route,
        'ownership': ownership.index,
        'eWayBillNo': eWayBillNo,
        'materialName': materialName,
        'loadingPoint': loadingPoint,
        'unloadingPoint': unloadingPoint,
        'loadingState': loadingState,
        'unloadingState': unloadingState,
        'consignorPhone': consignorPhone,
        'consignorEmail': consignorEmail,
        'consignorGstin': consignorGstin,
        'freightBilled': freightBilled,
        'paymentReceived': paymentReceived,
        'diesel': diesel,
        'toll': toll,
        'driverExp': driverExp,
        'materialLoss': materialLoss,
        'marketTruckFreight': marketTruckFreight,
        'marketAdvancePaid': marketAdvancePaid,
        'penalties': penalties,
        'tdsDeduction': tdsDeduction,
        'distanceKm': distanceKm,
        'fuelEconomy': fuelEconomy,
        'driverName': driverName,
        'paymentTermsDays': paymentTermsDays,
        'lrNotes': lrNotes,
        'gstType': gstType.index,
        'gstRate': gstRate,
        'isGstInclusive': isGstInclusive,
        'weightTons': weightTons,
        'weightUnit': weightUnit,
        'dispatchedAt': dispatchedAt,
        'estimatedArrival': estimatedArrival,
        'isInTransit': isInTransit,
        'platformCommission': platformCommission,
        'consignorCommission': consignorCommission,
        'materialInvoiceNo': materialInvoiceNo,
        'invoiceItems': invoiceItems.map((i) => i.toJson()).toList()
      };
  factory TripLedger.fromJson(Map<String, dynamic> j) => TripLedger(
      id: j['id'] ?? "TRP${math.Random().nextInt(9999)}",
      date: j['date'] ?? "",
      partyName: j['partyName'] ?? "",
      vehicleNo: j['vehicleNo'] ?? "",
      route: j['route'] ?? "",
      ownership: VehicleOwnership.values[j['ownership'] ?? 0],
      eWayBillNo: j['eWayBillNo'] ?? "PENDING",
      materialName: j['materialName'] ?? "General Goods",
      loadingPoint: j['loadingPoint'] ?? "",
      unloadingPoint: j['unloadingPoint'] ?? "",
      loadingState: j['loadingState'] ?? "",
      unloadingState: j['unloadingState'] ?? "",
      consignorPhone: j['consignorPhone'] ?? "",
      consignorEmail: j['consignorEmail'] ?? "",
      consignorGstin: j['consignorGstin'] ?? "",
      freightBilled: (j['freightBilled'] as num? ?? 0).toDouble(),
      paymentReceived: (j['paymentReceived'] as num? ?? 0).toDouble(),
      diesel: (j['diesel'] as num? ?? 0).toDouble(),
      toll: (j['toll'] as num? ?? 0).toDouble(),
      driverExp: (j['driverExp'] as num? ?? 0).toDouble(),
      materialLoss: (j['materialLoss'] as num? ?? 0).toDouble(),
      marketTruckFreight: (j['marketTruckFreight'] as num? ?? 0).toDouble(),
      marketAdvancePaid: (j['marketAdvancePaid'] as num? ?? 0).toDouble(),
      penalties: (j['penalties'] as num? ?? 0).toDouble(),
      tdsDeduction: (j['tdsDeduction'] as num? ?? 0).toDouble(),
      distanceKm: (j['distanceKm'] as num? ?? 0).toDouble(),
      fuelEconomy: (j['fuelEconomy'] as num? ?? 3.5).toDouble(),
      driverName: j['driverName'],
      paymentTermsDays: j['paymentTermsDays'] ?? 30,
      lrNotes: j['lrNotes'] ?? "",
      gstType: GstType.values[j['gstType'] ?? 0],
      gstRate: (j['gstRate'] as num? ?? 0).toDouble(),
      isGstInclusive: j['isGstInclusive'] ?? false,
      weightTons: (j['weightTons'] as num? ?? 0).toDouble(),
      weightUnit: j['weightUnit'] ?? "MT",
      dispatchedAt: j['dispatchedAt'] ?? '',
      estimatedArrival: j['estimatedArrival'] ?? '',
      isInTransit: j['isInTransit'] ?? false,
      platformCommission: (j['platformCommission'] as num? ?? 0).toDouble(),
      consignorCommission: (j['consignorCommission'] as num? ?? 0).toDouble(),
      materialInvoiceNo: j['materialInvoiceNo'] ?? '',
      invoiceItems: (j['invoiceItems'] as List? ?? [])
          .map((i) => InvoiceItem.fromJson(i))
          .toList());
}

class FleetDoc {
  String name;
  bool isUploaded;
  String expiryDate;
  String fileData;
  String filePath;
  String mimeType;
  // Extra extracted fields
  String engineNo;
  String chassisNo;
  String regNo;
  String ownerName;
  String insurer;
  String remarks;
  FleetDoc(
      {required this.name,
      this.isUploaded = false,
      this.expiryDate = "Pending",
      this.fileData = "",
      this.filePath = "",
      this.mimeType = "",
      this.engineNo = "",
      this.chassisNo = "",
      this.regNo = "",
      this.ownerName = "",
      this.insurer = "",
      this.remarks = ""});
  Map<String, dynamic> toJson() => {
        'name': name,
        'isUploaded': isUploaded,
        'expiryDate': expiryDate,
        'fileData': fileData,
        'filePath': filePath,
        'mimeType': mimeType,
        'engineNo': engineNo,
        'chassisNo': chassisNo,
        'regNo': regNo,
        'ownerName': ownerName,
        'insurer': insurer,
        'remarks': remarks
      };
  factory FleetDoc.fromJson(Map<String, dynamic> j) => FleetDoc(
      name: j['name'],
      isUploaded: j['isUploaded'] ?? false,
      expiryDate: j['expiryDate'] ?? "Pending",
      fileData: j['fileData'] ?? "",
      filePath: j['filePath'] ?? "",
      mimeType: j['mimeType'] ?? "",
      engineNo: j['engineNo'] ?? "",
      chassisNo: j['chassisNo'] ?? "",
      regNo: j['regNo'] ?? "",
      ownerName: j['ownerName'] ?? "",
      insurer: j['insurer'] ?? "",
      remarks: j['remarks'] ?? "");
}

class Asset {
  String id, number, type, payload;
  int tyreCount, axleCount;
  List<String> tyreSerials;
  List<Battery> batteries;
  List<FleetDoc> docs;
  String ownerName, ownerPhone;
  Asset(
      {required this.id,
      required this.number,
      required this.type,
      required this.payload,
      required this.tyreCount,
      required this.tyreSerials,
      required this.batteries,
      required this.docs,
      this.axleCount = 6,
      this.ownerName = "",
      this.ownerPhone = ""});
  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'type': type,
        'payload': payload,
        'tyreCount': tyreCount,
        'axleCount': axleCount,
        'tyreSerials': tyreSerials,
        'batteries': batteries.map((b) => (b).toJson()).toList(),
        'docs': docs.map((d) => (d).toJson()).toList(),
        'ownerName': ownerName,
        'ownerPhone': ownerPhone
      };
  factory Asset.fromJson(Map<String, dynamic> j) => Asset(
      id: j['id'],
      number: j['number'],
      type: j['type'],
      payload: j['payload'],
      tyreCount: j['tyreCount'],
      axleCount: j['axleCount'] ?? 6,
      tyreSerials: List<String>.from(j['tyreSerials']),
      batteries: j['batteries'] != null
          ? (j['batteries'] as List).map((b) => Battery.fromJson(b)).toList()
          : [],
      docs: j['docs'] != null
          ? (j['docs'] as List).map((d) => FleetDoc.fromJson(d)).toList()
          : [],
      ownerName: j['ownerName'] ?? "",
      ownerPhone: j['ownerPhone'] ?? "");
}

class MarketLoad {
  String id, route, details, vehicleType, materialType, postedDate;
  String originCity,
      originState,
      destCity,
      destState,
      originFactory,
      destFactory;
  double targetPrice, weightTons;
  BidStatus status;
  MarketLoad(
      {required this.id,
      required this.route,
      required this.details,
      required this.vehicleType,
      required this.targetPrice,
      this.status = BidStatus.pending,
      this.materialType = "",
      this.postedDate = "",
      this.originCity = "",
      this.originState = "",
      this.destCity = "",
      this.destState = "",
      this.originFactory = "",
      this.destFactory = "",
      this.weightTons = 0});
  Map<String, dynamic> toJson() => {
        'id': id,
        'route': route,
        'details': details,
        'vehicleType': vehicleType,
        'targetPrice': targetPrice,
        'status': status.index,
        'materialType': materialType,
        'postedDate': postedDate,
        'originCity': originCity,
        'originState': originState,
        'destCity': destCity,
        'destState': destState,
        'originFactory': originFactory,
        'destFactory': destFactory,
        'weightTons': weightTons
      };
  factory MarketLoad.fromJson(Map<String, dynamic> j) => MarketLoad(
      id: j['id'],
      route: j['route'],
      details: j['details'],
      vehicleType: j['vehicleType'],
      targetPrice: (j['targetPrice'] as num).toDouble(),
      status: BidStatus.values.firstWhere(
          (e) => e.index == (j['status'] as int? ?? 0),
          orElse: () => BidStatus.pending),
      materialType: j['materialType'] ?? "",
      postedDate: j['postedDate'] ?? "",
      originCity: j['originCity'] ?? "",
      originState: j['originState'] ?? "",
      destCity: j['destCity'] ?? "",
      destState: j['destState'] ?? "",
      originFactory: j['originFactory'] ?? "",
      destFactory: j['destFactory'] ?? "",
      weightTons: (j['weightTons'] as num? ?? 0).toDouble());
}

// ================================================================
// ROUTING ENGINE
// ================================================================
class RoutingEngine {
  // Get precise lat/lng from a placeId â€” like Uber resolving pickup/dropoff
  static Future<Map<String, double>?> _getLatLng(String placeId) async {
    try {
      final url = 'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId&fields=geometry&key=${AppConfig.googleMapsApiKey}';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (d['status'] == 'OK') {
          final loc = d['result']['geometry']['location'];
          return {
            'lat': (loc['lat'] as num).toDouble(),
            'lng': (loc['lng'] as num).toDouble()
          };
        }
      }
    } catch (_) {}
    return null;
  }

  // Geocode any text address to lat/lng â€” e.g. "JJ Motors, Ahmedabad" â†’ precise coords
  static Future<Map<String, double>?> _geocode(String address) async {
    if (address.isEmpty) return null;
    try {
      // Add 'India' hint to improve accuracy for Indian addresses
      final query = address.endsWith('India') ? address : '$address, India';
      final url = 'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=${Uri.encodeComponent(query)}&region=in&key=${AppConfig.googleMapsApiKey}';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (d['status'] == 'OK' && (d['results'] as List).isNotEmpty) {
          final loc = d['results'][0]['geometry']['location'];
          return {
            'lat': (loc['lat'] as num).toDouble(),
            'lng': (loc['lng'] as num).toDouble()
          };
        }
      }
    } catch (_) {}
    return null;
  }

  // Distance Matrix using precise lat/lng â€” same approach as Uber/Zomato
  static Future<int> _distanceFromCoords(
      Map<String, double> o, Map<String, double> d) async {
    try {
      final url = 'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=${o['lat']},${o['lng']}'
          '&destinations=${d['lat']},${d['lng']}'
          '&key=${AppConfig.googleMapsApiKey}&region=in&units=metric&mode=driving';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'OK') {
          final el = data['rows']?[0]?['elements']?[0];
          if (el?['status'] == 'OK') {
            return ((el['distance']['value'] as int) / 1000).round();
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  static Future<Map<String, dynamic>> calculate(
      {required String origin,
      required String destination,
      int axles = 6,
      double fuelEconomy = 3.5,
      String originPlaceId = '',
      String destPlaceId = ''}) async {
    int km = 0;
    String dataSource = 'offline';

    if (AppConfig.hasGoogleMaps) {
      try {
        // STEP 1: Resolve both endpoints to precise lat/lng using placeId
        // This is how Uber/Zomato work â€” exact coordinates, not city names
        Map<String, double>? oCoords, dCoords;

        // Origin: placeId is most precise (factory gate coords), then geocode full name
        if (originPlaceId.isNotEmpty) {
          oCoords = await _getLatLng(originPlaceId);
        }
        if (oCoords == null && origin.isNotEmpty) {
          // Geocode the specific place name â€” much more accurate than city alone
          oCoords = await _geocode(origin);
        }

        // Destination: same
        if (destPlaceId.isNotEmpty) {
          dCoords = await _getLatLng(destPlaceId);
        }
        if (dCoords == null && destination.isNotEmpty) {
          dCoords = await _geocode(destination);
        }

        debugPrint(
            'Distance calc: origin=${oCoords?['lat']},${oCoords?['lng']} dest=${dCoords?['lat']},${dCoords?['lng']}');

        // STEP 2: Drive distance between exact GPS coords
        if (oCoords != null && dCoords != null) {
          km = await _distanceFromCoords(oCoords, dCoords);
          if (km > 0) {
            dataSource = (originPlaceId.isNotEmpty || destPlaceId.isNotEmpty)
                ? 'google_precise'
                : 'google_geocoded';
          }
        }
      } catch (e) {
        dataSource = 'exception:$e';
      }
    }

    // STEP 3: Offline fallback (inter-city only â€” won't help local routes)
    if (km == 0) {
      km = _fallback(origin.toLowerCase(), destination.toLowerCase());
      if (km > 0) dataSource = 'smart_engine';
    }

    if (km == 0) {
      return {
        'km': 0,
        'diesel': 0,
        'toll': 0,
        'axles': axles,
        'source': 'not_found'
      };
    }
    final diesel = (km / fuelEconomy) * AppConfig.defaultDieselPrice;
    final tollRate = kTollPerAxlePerKm[axles] ?? 2.40;
    final toll = (km * tollRate).round();
    return {
      'km': km,
      'diesel': diesel.round(),
      'toll': toll,
      'axles': axles,
      'source': dataSource
    };
  }

  // Get place suggestions for companies/establishments â€” every business on Google Maps
  static Future<List<Map<String, String>>> getCompanySuggestions(
      String query) async {
    if (query.length < 2) return [];
    if (AppConfig.googleMapsApiKey.isEmpty) return [];
    try {
      // Use both establishment type for companies AND geocode for areas
      final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(query)}'
          '&components=country:in'
          '&types=establishment'
          '&language=en'
          '&key=${AppConfig.googleMapsApiKey}';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final preds = data['predictions'] as List? ?? [];
        return preds.take(10).map((p) {
          final desc = p['description'] as String? ?? '';
          final terms = p['terms'] as List? ?? [];
          // First term = company name, rest = address
          final name = terms.isNotEmpty
              ? (terms[0]['value'] as String? ?? desc.split(',').first.trim())
              : desc.split(',').first.trim();
          final location = terms.length > 1
              ? terms
                  .skip(1)
                  .map((t) => t['value'] as String? ?? '')
                  .where((s) => s.isNotEmpty)
                  .join(', ')
              : '';
          final placeId = p['place_id'] as String? ?? '';
          return {
            'name': name,
            'full': desc,
            'location': location,
            'placeId': placeId
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  static int _fallback(String o, String d) {
    // Normalize: remove spaces, special chars, lowercase
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final a = norm(o);
    final b = norm(d);
    // Key = sorted alphabetically so ahmedabad-mumbai == mumbai-ahmedabad
    String key(String x, String y) {
      final pair = [x, y]..sort();
      return '${pair[0]}_${pair[1]}';
    }

    // Precise road distances (km) from NHAI/Google Maps data
    final routes = <String, int>{
      key('ahmedabad', 'mumbai'): 527,
      key('ahmedabad', 'delhi'): 935,
      key('ahmedabad', 'surat'): 265,
      key('ahmedabad', 'amritsar'): 1153,
      key('ahmedabad', 'pune'): 655,
      key('ahmedabad', 'jaipur'): 678,
      key('ahmedabad', 'indore'): 585,
      key('ahmedabad', 'nagpur'): 872,
      key('ahmedabad', 'hyderabad'): 1048,
      key('ahmedabad', 'bangalore'): 1350,
      key('ahmedabad', 'kolkata'): 2020,
      key('ahmedabad', 'chandigarh'): 1085,
      key('ahmedabad', 'lucknow'): 1255,
      key('ahmedabad', 'bhopal'): 710,
      key('ahmedabad', 'raipur'): 1175,
      key('ahmedabad', 'patna'): 1610,
      key('ahmedabad', 'guwahati'): 2580,
      key('ahmedabad', 'dehradun'): 1145,
      key('ahmedabad', 'kochi'): 1945,
      key('ahmedabad', 'chennai'): 1635,
      key('ahmedabad', 'visakhapatnam'): 1485,
      key('surat', 'mumbai'): 285,
      key('surat', 'pune'): 384,
      key('surat', 'delhi'): 1200,
      key('surat', 'nagpur'): 740,
      key('surat', 'bangalore'): 1185,
      key('surat', 'hyderabad'): 915,
      key('bharuch', 'mumbai'): 330,
      key('bharuch', 'surat'): 82,
      key('bharuch', 'ahmedabad'): 180,
      key('bharuch', 'delhi'): 905,
      key('bharuch', 'pune'): 435,
      key('bharuch', 'indore'): 405,
      key('ankleshwar', 'surat'): 30,
      key('ankleshwar', 'mumbai'): 315,
      key('ankleshwar', 'ahmedabad'): 185,
      key('hazira', 'ahmedabad'): 278,
      key('hazira', 'surat'): 22,
      key('hazira', 'mumbai'): 305,
      key('dahej', 'ahmedabad'): 198,
      key('dahej', 'surat'): 150,
      key('dahej', 'mumbai'): 395,
      key('kandla', 'ahmedabad'): 365,
      key('kandla', 'mumbai'): 790,
      key('kandla', 'delhi'): 1200,
      key('mundra', 'ahmedabad'): 370,
      key('mundra', 'mumbai'): 830,
      key('vapi', 'mumbai'): 195,
      key('vapi', 'surat'): 65,
      key('vapi', 'pune'): 330,
      key('mumbai', 'delhi'): 1420,
      key('mumbai', 'bangalore'): 985,
      key('mumbai', 'hyderabad'): 710,
      key('mumbai', 'pune'): 155,
      key('mumbai', 'nagpur'): 825,
      key('mumbai', 'nashik'): 165,
      key('mumbai', 'kolkata'): 2060,
      key('mumbai', 'chandigarh'): 1665,
      key('mumbai', 'jaipur'): 1150,
      key('mumbai', 'indore'): 590,
      key('mumbai', 'bhopal'): 775,
      key('mumbai', 'chennai'): 1340,
      key('mumbai', 'kochi'): 1660,
      key('delhi', 'jaipur'): 268,
      key('delhi', 'amritsar'): 448,
      key('delhi', 'lucknow'): 548,
      key('delhi', 'chandigarh'): 245,
      key('delhi', 'kolkata'): 1505,
      key('delhi', 'bangalore'): 2150,
      key('delhi', 'hyderabad'): 1570,
      key('delhi', 'nagpur'): 1080,
      key('delhi', 'bhopal'): 776,
      key('delhi', 'indore'): 963,
      key('delhi', 'patna'): 1000,
      key('delhi', 'dehradun'): 295,
      key('delhi', 'haridwar'): 230,
      key('delhi', 'agra'): 210,
      key('delhi', 'meerut'): 70,
      key('delhi', 'varanasi'): 820,
      key('delhi', 'kanpur'): 480,
      key('delhi', 'jodhpur'): 610,
      key('delhi', 'udaipur'): 670,
      key('chandigarh', 'amritsar'): 230,
      key('chandigarh', 'ludhiana'): 100,
      key('chandigarh', 'jalandhar'): 148,
      key('chandigarh', 'dehradun'): 170,
      key('amritsar', 'ludhiana'): 135,
      key('amritsar', 'jalandhar'): 80,
      key('ludhiana', 'panipat'): 210,
      key('panipat', 'delhi'): 90,
      key('jaipur', 'jodhpur'): 335,
      key('jaipur', 'udaipur'): 395,
      key('jaipur', 'kota'): 252,
      key('jaipur', 'ajmer'): 135,
      key('jaipur', 'bikaner'): 330,
      key('lucknow', 'kanpur'): 82,
      key('lucknow', 'varanasi'): 320,
      key('lucknow', 'agra'): 365,
      key('lucknow', 'patna'): 585,
      key('agra', 'mathura'): 55,
      key('agra', 'varanasi'): 580,
      key('indore', 'bhopal'): 195,
      key('indore', 'nagpur'): 480,
      key('indore', 'hyderabad'): 720,
      key('bhopal', 'nagpur'): 350,
      key('bhopal', 'raipur'): 487,
      key('nagpur', 'hyderabad'): 500,
      key('nagpur', 'raipur'): 300,
      key('nagpur', 'kolkata'): 1065,
      key('hyderabad', 'bangalore'): 570,
      key('hyderabad', 'chennai'): 630,
      key('hyderabad', 'visakhapatnam'): 625,
      key('hyderabad', 'kochi'): 1155,
      key('hyderabad', 'kolkata'): 1495,
      key('bangalore', 'chennai'): 347,
      key('bangalore', 'kochi'): 548,
      key('bangalore', 'mysuru'): 148,
      key('bangalore', 'mangaluru'): 350,
      key('bangalore', 'coimbatore'): 360,
      key('bangalore', 'hubli'): 410,
      key('bangalore', 'visakhapatnam'): 985,
      key('chennai', 'coimbatore'): 500,
      key('chennai', 'madurai'): 462,
      key('chennai', 'kochi'): 686,
      key('chennai', 'thoothukudi'): 592,
      key('visakhapatnam', 'vijayawada'): 350,
      key('visakhapatnam', 'kakinada'): 168,
      key('visakhapatnam', 'kolkata'): 1060,
      key('vijayawada', 'hyderabad'): 272,
      key('kolkata', 'patna'): 580,
      key('kolkata', 'bhubaneswar'): 440,
      key('kolkata', 'ranchi'): 390,
      key('kolkata', 'jamshedpur'): 295,
      key('kolkata', 'guwahati'): 1000,
      key('bhubaneswar', 'paradip'): 105,
      key('patna', 'ranchi'): 330,
      key('ranchi', 'jamshedpur'): 130,
      key('raipur', 'nagpur'): 300,
      key('raipur', 'bhubaneswar'): 440,
      key('pune', 'bangalore'): 840,
      key('pune', 'hyderabad'): 560,
      key('pune', 'nagpur'): 730,
      key('jnpt', 'mumbai'): 60,
      key('haldia', 'kolkata'): 120,
      key('kochi', 'thiruvananthapuram'): 210,
      // Punjab routes
      key('bathinda', 'delhi'): 280,
      key('bathinda', 'chandigarh'): 210,
      key('bathinda', 'ludhiana'): 110,
      key('bathinda', 'amritsar'): 175,
      key('bathinda', 'jaipur'): 490,
      key('bathinda', 'ahmedabad'): 1030,
      key('bathinda', 'surat'): 1270,
      key('bathinda', 'vapi'): 1295,
      key('bathinda', 'mumbai'): 1490,
      key('bathinda', 'panipat'): 255,
      key('bathinda', 'hisar'): 155,
      key('bathinda', 'rohtak'): 295,
      key('bathinda', 'ambala'): 175,
      key('bathinda', 'karnal'): 225,
      // Daman & Diu routes
      key('daman', 'mumbai'): 193,
      key('daman', 'vapi'): 13,
      key('daman', 'surat'): 110,
      key('daman', 'ahmedabad'): 340,
      key('daman', 'pune'): 360,
      key('diu', 'ahmedabad'): 380,
      key('diu', 'rajkot'): 225,
      key('diu', 'jamnagar'): 260,
      // More UP routes
      key('gorakhpur', 'lucknow'): 270,
      key('gorakhpur', 'varanasi'): 100,
      key('gorakhpur', 'patna'): 245,
      key('bareilly', 'delhi'): 250,
      key('bareilly', 'lucknow'): 250,
      key('moradabad', 'delhi'): 165,
      key('meerut', 'delhi'): 70,
      key('meerut', 'agra'): 295,
      key('aligarh', 'delhi'): 140,
      key('aligarh', 'agra'): 60,
      // Rajasthan industrial
      key('bhiwadi', 'delhi'): 60,
      key('bhiwadi', 'jaipur'): 175,
      key('neemrana', 'delhi'): 100,
      key('neemrana', 'jaipur'): 155,
      key('alwar', 'delhi'): 150,
      key('alwar', 'jaipur'): 147,
      // Himachal Pradesh
      key('baddi', 'chandigarh'): 40,
      key('baddi', 'delhi'): 290,
      key('solan', 'chandigarh'): 45,
      key('paonta sahib', 'dehradun'): 55,
      key('paonta sahib', 'chandigarh'): 95,
      // Uttarakhand industrial
      key('rudrapur', 'delhi'): 250,
      key('rudrapur', 'haridwar'): 100,
      key('pantnagar', 'delhi'): 265,
      key('pantnagar', 'haldwani'): 20,
      key('kashipur', 'delhi'): 235,
      key('roorkee', 'haridwar'): 30,
      key('roorkee', 'delhi'): 175,
      // Goa routes
      key('panaji', 'mumbai'): 598,
      key('panaji', 'pune'): 452,
      key('panaji', 'bangalore'): 565,
      key('mormugao', 'mumbai'): 600,
      // Odisha
      key('rourkela', 'bhubaneswar'): 335,
      key('rourkela', 'ranchi'): 170,
      key('rourkela', 'jamshedpur'): 200,
      key('angul', 'bhubaneswar'): 140,
      key('talcher', 'bhubaneswar'): 170,
      key('jharsuguda', 'raipur'): 175,
      key('jharsuguda', 'ranchi'): 200,
      // Chhattisgarh
      key('bhilai', 'raipur'): 30,
      key('durg', 'raipur'): 28,
      key('korba', 'raipur'): 190,
      key('bilaspur', 'raipur'): 110,
      key('raigarh', 'raipur'): 185,
      // South India extras
      key('hosur', 'bangalore'): 45,
      key('hosur', 'chennai'): 360,
      key('tiruppur', 'coimbatore'): 55,
      key('tiruppur', 'chennai'): 465,
      key('erode', 'coimbatore'): 80,
      key('salem', 'chennai'): 340,
      key('salem', 'coimbatore'): 145,
      key('vellore', 'chennai'): 140,
      key('nellore', 'chennai'): 175,
      key('nellore', 'hyderabad'): 475,
      key('tirupati', 'chennai'): 150,
      key('kurnool', 'hyderabad'): 215,
      key('anantapur', 'bangalore'): 195,
      key('bellary', 'bangalore'): 295,
      key('hubli', 'bangalore'): 410,
      key('belgaum', 'pune'): 530,
      key('belgaum', 'bangalore'): 490,
      key('mangaluru', 'bangalore'): 350,
      key('mangaluru', 'goa'): 240,
      key('gulbarga', 'hyderabad'): 220,
      key('gulbarga', 'bangalore'): 620,
      // Kerala extras
      key('kozhikode', 'bangalore'): 375,
      key('kozhikode', 'kochi'): 215,
      key('thrissur', 'kochi'): 80,
      key('palakkad', 'coimbatore'): 60,
      key('palakkad', 'kochi'): 145,
      key('kollam', 'thiruvananthapuram'): 72,
    };
    final k = key(a, b);
    if (routes.containsKey(k)) return routes[k]!;
    // Partial match: check if any key contains both city fragments
    for (final e in routes.entries) {
      final parts = e.key.split('_');
      if (parts.length == 2) {
        final p0 = parts[0];
        final p1 = parts[1];
        final aMatch =
            a.contains(p0) || p0.contains(a.length > 4 ? a.substring(0, 4) : a);
        final bMatch =
            b.contains(p1) || p1.contains(b.length > 4 ? b.substring(0, 4) : b);
        final aMatch2 =
            a.contains(p1) || p1.contains(a.length > 4 ? a.substring(0, 4) : a);
        final bMatch2 =
            b.contains(p0) || p0.contains(b.length > 4 ? b.substring(0, 4) : b);
        if ((aMatch && bMatch) || (aMatch2 && bMatch2)) return e.value;
      }
    }
    // Last resort: rough estimate
    return (a.length + b.length) * 35 + 250;
  }

  static Future<List<Map<String, String>>> getCitySuggestions(
      String query) async {
    if (query.length < 2) return [];
    // Always try Google Places first if API key is present
    if (AppConfig.googleMapsApiKey.isNotEmpty) {
      try {
        final url =
            'https://maps.googleapis.com/maps/api/place/autocomplete/json'
            '?input=${Uri.encodeComponent(query)}'
            '&components=country:in'
            '&types=(cities)'
            '&key=${AppConfig.googleMapsApiKey}';
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final preds = data['predictions'] as List? ?? [];
          if (preds.isNotEmpty) {
            return preds.take(8).map((p) {
              final desc = p['description'] as String? ?? '';
              final terms = p['terms'] as List? ?? [];
              final city = terms.isNotEmpty
                  ? (terms[0]['value'] as String? ?? '')
                  : desc.split(',').first.trim();
              // State is usually the 2nd-to-last term (before 'India')
              final state = terms.length >= 2
                  ? (terms[terms.length >= 3 ? terms.length - 2 : 1]['value']
                          as String? ??
                      '')
                  : '';
              final full = state.isNotEmpty ? '$city, $state' : city;
              return {
                'city': city,
                'state': state,
                'full': full,
                'placeId': p['place_id'] as String? ?? ''
              };
            }).toList();
          }
        }
      } catch (_) {}
    }
    // Local fallback â€” fast, always works
    final q = query.toLowerCase().trim();
    final matches = kIndianCities
        .where((c) =>
            c['city']!.toLowerCase().startsWith(q) ||
            c['city']!.toLowerCase().contains(q) ||
            (c['state'] ?? '').toLowerCase().contains(q))
        .toList();
    // Prioritize starts-with matches
    matches.sort((a, b) {
      final aStarts = a['city']!.toLowerCase().startsWith(q) ? 0 : 1;
      final bStarts = b['city']!.toLowerCase().startsWith(q) ? 0 : 1;
      return aStarts - bStarts;
    });
    return matches
        .take(8)
        .map((c) => {
              'city': c['city']!,
              'state': c['state']!,
              'full': c['full']!,
              'placeId': ''
            })
        .toList();
  }

  // Get place details (lat/lng) for distance matrix calls
  static Future<Map<String, double>?> getPlaceLatLng(String placeId) async {
    if (AppConfig.googleMapsApiKey.isEmpty || placeId.isEmpty) return null;
    try {
      final url = 'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&fields=geometry'
          '&key=${AppConfig.googleMapsApiKey}';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final loc = data['result']?['geometry']?['location'];
        if (loc != null) {
          return {
            'lat': (loc['lat'] as num).toDouble(),
            'lng': (loc['lng'] as num).toDouble()
          };
        }
      }
    } catch (_) {}
    return null;
  }
}

// ================================================================
// MAIN
// ================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFFF8E1),
      statusBarIconBrightness: Brightness.light));
  // Initialize Firebase â€” requires google-services.json (Android) / GoogleService-Info.plist (iOS)
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseService.init();
    debugPrint('âœ… Firebase ready â€” cloud sync active');
  } catch (e) {
    debugPrint('âš ï¸ Firebase not configured â€” using local storage only: $e');
  }
  runApp(const RouteMasterApp());
}

class RouteMasterApp extends StatelessWidget {
  const RouteMasterApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Route Master ERP',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          primaryColor: const Color(0xFFFB8C00),
          scaffoldBackgroundColor: const Color(0xFFFFF8E1),
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFB8C00),
            brightness: Brightness.light,
            primary: const Color(0xFFFB8C00),
            secondary: const Color(0xFFFFA726),
            surface: const Color(0xFFFFF8E1),
            background: const Color(0xFFFFF8E1),
            onSurface: const Color(0xFF000000),
            onBackground: const Color(0xFF000000),
            onPrimary: const Color(0xFF000000),
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shadowColor: const Color(0x33000000),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: const Color(0xFFFFF8E1),
            surfaceTintColor: Colors.transparent,
          ),
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: Color(0xFFFB8C00),
            selectionColor: Color(0x44FB8C00),
            selectionHandleColor: Color(0xFFFB8C00),
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFFFFF8E1),
            titleTextStyle: TextStyle(
                color: Color(0xFF000000),
                fontSize: 16,
                fontWeight: FontWeight.w800),
            contentTextStyle: TextStyle(color: Color(0xFF000000), fontSize: 13),
          ),
          popupMenuTheme: const PopupMenuThemeData(
            color: Color(0xFFFFF8E1),
            textStyle: TextStyle(
                color: Color(0xFF000000),
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          dropdownMenuTheme: const DropdownMenuThemeData(
            textStyle: TextStyle(
                color: Color(0xFF000000),
                fontSize: 14,
                fontWeight: FontWeight.w500),
            menuStyle: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(Color(0xFFFFF8E1)),
            ),
          ),
          appBarTheme: const AppBarTheme(
            elevation: 2,
            scrolledUnderElevation: 2,
            backgroundColor: Color(0xFFFB8C00),
            foregroundColor: Color(0xFF000000),
            shadowColor: Color(0x33000000),
            titleTextStyle: TextStyle(
                color: Color(0xFF000000),
                fontWeight: FontWeight.w800,
                fontSize: 16),
            iconTheme: IconThemeData(color: Color(0xFF000000)),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 2,
              backgroundColor: const Color(0xFFFB8C00),
              foregroundColor: const Color(0xFF000000),
              shadowColor: const Color(0x33000000),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFFFF8E1),
            contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            isDense: false,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFB8C00))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFB8C00))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFFB8C00), width: 2)),
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            labelStyle: const TextStyle(
                color: Color(0xFF000000),
                fontWeight: FontWeight.w500,
                fontSize: 14),
            floatingLabelStyle: const TextStyle(
                color: Color(0xFFFB8C00),
                fontWeight: FontWeight.w700,
                fontSize: 12),
            hintStyle: const TextStyle(
                color: Color(0xFF777777),
                fontWeight: FontWeight.w400,
                fontSize: 14),
            helperStyle:
                const TextStyle(color: Color(0xFF777777), fontSize: 11),
            errorStyle: const TextStyle(
                color: Color(0xFFFF6B6B),
                fontSize: 11,
                fontWeight: FontWeight.w600),
            prefixIconColor: const Color(0xFF000000),
            suffixIconColor: const Color(0xFF000000),
          ),
          textTheme: const TextTheme().apply(
              bodyColor: Color(0xFF000000), displayColor: Color(0xFF000000)),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Color(0xFFFFF8E1),
            selectedItemColor: Color(0xFFFB8C00),
            unselectedItemColor: Color(0xFF777777),
            type: BottomNavigationBarType.fixed,
            elevation: 2,
            selectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
            unselectedLabelStyle: TextStyle(fontSize: 10),
          ),
        ),
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
      );
}

// ================================================================
// SPLASH
// ================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    Timer(const Duration(seconds: 3), () async {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('rm_session_active') ?? false;
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  isLoggedIn ? const MainShell() : const LoginScreen()));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      body: Stack(children: [
        // Warm morning gradient wash
        Positioned.fill(
            child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFF8ED), Color(0xFFFBF7F0), Color(0xFFF0EBE1)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        )),
        // Orange glow top-right
        Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFB8C00).withOpacity(0.3),
                  Colors.transparent
                ]),
              ),
            )),
        // Soft amber glow bottom-left
        Positioned(
            bottom: -40,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFFA726).withOpacity(0.25),
                  Colors.transparent
                ]),
              ),
            )),
        // Main content
        Center(
            child: FadeTransition(
          opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ScaleTransition(
              scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
              child: _buildLogo(),
            ),
            const SizedBox(height: 32),
            const Text("ROUTE MASTER",
                style: TextStyle(
                    color: Color(0xFF000000),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 7)),
            const SizedBox(height: 6),
            const Text("TRANSPORT ERP",
                style: TextStyle(
                    color: Color(0xFFFB8C00),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4)),
            const SizedBox(height: 4),
            const Text("India's Intelligent Fleet Platform",
                style: TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 11,
                    letterSpacing: 0.3)),
            const SizedBox(height: 60),
            SizedBox(
                width: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0xFFFFE0B2),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFB8C00)),
                    minHeight: 3,
                  ),
                )),
            const SizedBox(height: 14),
            const Text("LOADING...",
                style: TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3)),
          ]),
        )),
        Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _c, curve: Curves.easeIn),
              child: const Column(children: [
                Text("Powered by Route Master Technologies",
                    style: TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5)),
              ]),
            )),
      ]),
    );
  }

  Widget _buildLogo() => SizedBox(
        width: 120,
        height: 120,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFF3E0),
              border: Border.all(
                  color: const Color(0xFFFFA726).withOpacity(0.35), width: 2),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFFA726).withOpacity(0.15),
                    blurRadius: 30,
                    spreadRadius: 4),
                const BoxShadow(
                    color: Color(0xFFFFF8E1), blurRadius: 8, spreadRadius: 2),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFF8E1),
              boxShadow: [
                BoxShadow(
                    color: Color(0x33FB8C00), blurRadius: 10, spreadRadius: 1)
              ],
            ),
          ),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.local_shipping_rounded,
                color: Color(0xFFFB8C00), size: 40),
            Container(
              width: 50,
              height: 2.5,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: const Color(0xFFFB8C00).withOpacity(0.4),
              ),
            ),
          ]),
          Positioned(
              bottom: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFA726),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFFFFA726).withOpacity(0.35),
                          blurRadius: 6)
                    ]),
                child: const Text("RM",
                    style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
              )),
        ]),
      );
}

// ================================================================
// LOGIN
// ================================================================

// ================================================================
// REGISTRATION / KYC SCREEN â€” first-time onboarding
// ================================================================
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  int _step = 0; // 0=company, 1=docs, 2=bank
  bool _saving = false;

  // Company info
  final _company = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gst = TextEditingController();
  final _pan = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  String _fleetType = 'Tanker';
  String _fleetSize = '1â€“5';

  // Bank
  final _bankName = TextEditingController();
  final _accNo = TextEditingController();
  final _ifsc = TextEditingController();
  final _branch = TextEditingController();

  // Docs uploaded flags
  bool _gstUploaded = false,
      _panUploaded = false,
      _rcUploaded = false,
      _udyamUploaded = false,
      _cancelledChequeUploaded = false;

  Widget _field(TextEditingController ctrl, String label,
          {TextInputType? kb, String? hint, bool required = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: ctrl,
          keyboardType: kb,
          style: const TextStyle(
              color: Color(0xFF000000),
              fontSize: 15,
              fontWeight: FontWeight.w500),
          cursorColor: const Color(0xFF000000),
          decoration: InputDecoration(
            labelText: required ? "$label *" : label,
            labelStyle: const TextStyle(
                color: Color(0xFF000000),
                fontSize: 14,
                fontWeight: FontWeight.w500),
            floatingLabelStyle: const TextStyle(
                color: Color(0xFFFB8C00),
                fontWeight: FontWeight.w800,
                fontSize: 12),
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF777777), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFFFFF8E1),
            contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFB8C00))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFB8C00))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFFB8C00), width: 2)),
          ),
        ),
      );

  Widget _docTile(
          String name, String desc, bool uploaded, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: uploaded
                ? Colors.green.withOpacity(0.1)
                : const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: uploaded
                    ? Colors.green.withOpacity(0.4)
                    : const Color(0xFFFB8C00)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: uploaded
                    ? Colors.green.withOpacity(0.18)
                    : const Color(0xFFFFEBCD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                  uploaded ? Icons.check_circle : Icons.upload_file_rounded,
                  color: uploaded ? Colors.green : const Color(0xFFFB8C00),
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: uploaded
                              ? const Color(0xFF000000)
                              : const Color(0xFF000000))),
                  Text(desc,
                      style: const TextStyle(
                          color: Color(0xFF333333), fontSize: 11)),
                ])),
            Text(uploaded ? "Uploaded âœ“" : "Tap to upload",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: uploaded ? Colors.green : const Color(0xFFFB8C00))),
          ]),
        ),
      );

  Future<void> _uploadDoc(String docName, Function(bool) onDone) async {
    try {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (img != null) {
        onDone(true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            content: Text("$docName uploaded successfully")));
      }
    } catch (_) {
      try {
        final file = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
        if (file != null) {
          onDone(true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              content: Text("$docName uploaded successfully")));
        }
      } catch (_) {
        onDone(true); // simulate for demo
      }
    }
  }

  Future<void> _saveAndContinue() async {
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = UserProfile(
        companyName: _company.text.isEmpty ? "My Company" : _company.text,
        phone: _phone.text,
        email: _email.text,
        gstin: _gst.text,
        panNumber: _pan.text,
        address: _address.text,
        bankName: _bankName.text,
        bankAccount: _accNo.text,
        bankIfsc: _ifsc.text,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fm_profile', jsonEncode(profile.toJson()));
      await prefs.setBool('rm_registration_done', true);
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainShell()));
    } catch (_) {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const MainShell()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = ["Company Info", "Documents", "Bank Details"];
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFB8C00),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Complete Your Profile",
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Color(0xFF000000))),
          Text("Step ${_step + 1} of 3 â€” ${steps[_step]}",
              style: const TextStyle(fontSize: 11, color: Color(0xFF333333))),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const MainShell())),
            child: const Text("Skip for now",
                style: TextStyle(color: Color(0xFF333333), fontSize: 12)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: (_step + 1) / 3,
            backgroundColor: const Color(0xFFFFF0D5),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFB8C00)),
          ),
        ),
      ),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_step == 0) ...[
            const Text("Company & Owner Details",
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF000000))),
            const Text("Used on LR, Invoice, and all official documents",
                style: TextStyle(color: Color(0xFF333333), fontSize: 12)),
            const SizedBox(height: 20),
            _field(_company, "Company / Firm Name",
                hint: "e.g. Mahek Logistics Pvt. Ltd."),
            _field(_ownerName, "Owner / Proprietor Name"),
            _field(_phone, "Mobile Number",
                kb: TextInputType.phone, hint: "+91 XXXXX XXXXX"),
            _field(_email, "Email Address",
                kb: TextInputType.emailAddress, required: false),
            _field(_gst, "GSTIN", hint: "27AAAAA0000A1Z5", required: false),
            _field(_pan, "PAN Number", hint: "AAAAA0000A", required: false),
            _field(_address, "Registered Address"),
            Row(children: [
              Expanded(child: _field(_city, "City")),
              const SizedBox(width: 12),
              Expanded(child: _field(_state, "State")),
            ]),
            _field(_pincode, "Pincode",
                kb: TextInputType.number, required: false),
            const SizedBox(height: 8),
            const Text("Fleet Type",
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF000000))),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                children: ['Tanker', 'Container', 'Truck', 'Trailer', 'Mixed']
                    .map((t) => GestureDetector(
                          onTap: () => setState(() => _fleetType = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: _fleetType == t
                                  ? const Color(0xFFFB8C00)
                                  : const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _fleetType == t
                                      ? const Color(0xFFFB8C00)
                                      : const Color(0xFFFB8C00)),
                            ),
                            child: Text(t,
                                style: TextStyle(
                                    color: _fleetType == t
                                        ? const Color(0xFF000000)
                                        : const Color(0xFF333333),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                          ),
                        ))
                    .toList()),
            const SizedBox(height: 8),
            const Text("Fleet Size",
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF000000))),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                children: ['1â€“5', '6â€“15', '16â€“50', '50+']
                    .map((s) => GestureDetector(
                          onTap: () => setState(() => _fleetSize = s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: _fleetSize == s
                                  ? const Color(0xFFFB8C00)
                                  : const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _fleetSize == s
                                      ? const Color(0xFFFB8C00)
                                      : const Color(0xFFFB8C00)),
                            ),
                            child: Text(s,
                                style: TextStyle(
                                    color: _fleetSize == s
                                        ? const Color(0xFF000000)
                                        : const Color(0xFF333333),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                          ),
                        ))
                    .toList()),
          ] else if (_step == 1) ...[
            const Text("Business Documents",
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF000000))),
            const Text("Required for KredX financing and platform verification",
                style: TextStyle(color: Color(0xFF333333), fontSize: 12)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFB8C00).withOpacity(0.3))),
              child: Row(children: [
                Icon(Icons.info_outline,
                    color: const Color(0xFFFB8C00), size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        "All documents are stored securely. JPG, PNG and PDF accepted. Max 10MB per file.",
                        style: TextStyle(
                            color: const Color(0xFF333333), fontSize: 11)))
              ]),
            ),
            _docTile(
                "GST Certificate",
                "Business registration proof",
                _gstUploaded,
                () => _uploadDoc("GST Certificate",
                    (v) => setState(() => _gstUploaded = v))),
            _docTile(
                "PAN Card",
                "Company or proprietor PAN",
                _panUploaded,
                () => _uploadDoc(
                    "PAN Card", (v) => setState(() => _panUploaded = v))),
            _docTile(
                "RC Book (Sample)",
                "Any one vehicle RC for verification",
                _rcUploaded,
                () => _uploadDoc(
                    "RC Book", (v) => setState(() => _rcUploaded = v))),
            _docTile(
                "Udyam / MSME Certificate",
                "If registered (optional)",
                _udyamUploaded,
                () => _uploadDoc("Udyam Certificate",
                    (v) => setState(() => _udyamUploaded = v))),
            _docTile(
                "Cancelled Cheque",
                "For bank account verification",
                _cancelledChequeUploaded,
                () => _uploadDoc("Cancelled Cheque",
                    (v) => setState(() => _cancelledChequeUploaded = v))),
          ] else ...[
            const Text("Bank Account Details",
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF000000))),
            const Text("For KredX disbursements and invoice payments",
                style: TextStyle(color: Color(0xFF333333), fontSize: 12)),
            const SizedBox(height: 20),
            _field(_bankName, "Bank Name", hint: "e.g. State Bank of India"),
            _field(_accNo, "Account Number", kb: TextInputType.number),
            _field(_ifsc, "IFSC Code", hint: "SBIN0001234"),
            _field(_branch, "Branch Name", required: false),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFB8C00),
                foregroundColor: const Color(0xFF000000),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _saving ? null : _saveAndContinue,
              child: _saving
                  ? const CircularProgressIndicator(
                      color: Color(0xFF000000), strokeWidth: 2)
                  : Text(_step < 2 ? "Continue" : "Complete Setup â†’",
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF000000))),
            ),
          ),
        ]),
      )),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _sent = false;
  bool _loading = false;
  String? _verificationId;
  String? _errorMsg;
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  Future<void> _sendOTP() async {
    final raw = _phone.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (raw.length < 10) {
      setState(() => _errorMsg = 'Enter a valid 10-digit mobile number');
      return;
    }
    final phone = raw.startsWith('+91')
        ? raw
        : '+91${raw.replaceAll(RegExp(r'^0+'), '')}';
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    await FirebaseService.sendOTP(
      phone: phone,
      onCodeSent: (vid) {
        if (mounted) {
          setState(() {
            _verificationId = vid;
            _sent = true;
            _loading = false;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorMsg =
                'OTP failed: ${e.toString().replaceAll(RegExp(r'\[.*?\]'), '').trim()}';
          });
        }
      },
    );
  }

  Future<void> _verifyOTP() async {
    if (_verificationId == null) {
      setState(() => _errorMsg = 'Request OTP first');
      return;
    }
    if (_otp.text.trim().length < 6) {
      setState(() => _errorMsg = 'Enter 6-digit OTP');
      return;
    }
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final ok = await FirebaseService.verifyOTP(
          verificationId: _verificationId!, otp: _otp.text.trim());
      if (!mounted) return;
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('rm_session_active', true);
        final isNew = prefs.getString('fm_profile') == null;
        if (!mounted) return;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    isNew ? const RegistrationScreen() : const MainShell()));
      } else {
        setState(() {
          _loading = false;
          _errorMsg = 'Incorrect OTP. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Verification error. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: Stack(children: [
        Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
          Color(0xFFFFF8E1),
          Color(0xFFFFEBCD),
          Color(0xFFFFE0B2),
          Color(0xFFFFF8E1)
        ], stops: [
          0.0,
          0.3,
          0.7,
          1.0
        ], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
        CustomPaint(painter: _RouteBgPainter(), size: Size.infinite),
        Positioned(
            top: -80,
            left: -80,
            child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFFFB8C00).withOpacity(0.2),
                      Colors.transparent
                    ])))),
        Positioned(
            bottom: -40,
            right: -40,
            child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFFFFA726).withOpacity(0.15),
                      Colors.transparent
                    ])))),
        SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(children: [
                      Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(colors: [
                                Color(0xFFFFA726),
                                Color(0xFFFB8C00)
                              ]),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFFFFA726)
                                        .withOpacity(0.4),
                                    blurRadius: 20)
                              ]),
                          child: const Icon(Icons.local_shipping_rounded,
                              color: Color(0xFF000000), size: 36)),
                      const SizedBox(height: 16),
                      const Text("Route Master ERP",
                          style: TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      const Text("Sign in to manage your fleet",
                          style: TextStyle(
                              color: Color(0xFF333333), fontSize: 14)),
                      const SizedBox(height: 40),
                      Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 40,
                                    offset: const Offset(0, 20))
                              ]),
                          child: Column(children: [
                            if (!_sent) ...[
                              TextField(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                      labelText: "Mobile Number",
                                      hintText: "+91 98765 43210",
                                      prefixIcon: const Icon(Icons.phone,
                                          color: Color(0xFFFB8C00)),
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      labelStyle: const TextStyle(
                                          color: Color(0xFF000000),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500),
                                      floatingLabelStyle: const TextStyle(
                                          color: Color(0xFFFB8C00),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFFA726),
                                              width: 2)))),
                              const SizedBox(height: 20),
                              SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFFB8C00),
                                          foregroundColor:
                                              const Color(0xFF000000),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12))),
                                      onPressed: _loading ? null : _sendOTP,
                                      child: _loading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Color(0xFF000000)))
                                          : const Text("Send OTP",
                                              style: TextStyle(
                                                  color: Color(0xFF000000),
                                                  fontSize: 16,
                                                  fontWeight:
                                                      FontWeight.bold)))),
                            ] else ...[
                              Text(
                                  "OTP sent to +91 ${_phone.text.replaceAll(RegExp(r"^\+?91"), "").trim()}",
                                  style: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 15),
                              TextField(
                                  controller: _otp,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 28,
                                      letterSpacing: 12,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF000000)),
                                  maxLength: 6,
                                  decoration: InputDecoration(
                                      counterText: "",
                                      labelText: "6-Digit OTP",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      labelStyle: const TextStyle(
                                          color: Color(0xFF000000),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500),
                                      floatingLabelStyle: const TextStyle(
                                          color: Color(0xFFFB8C00),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFFA726),
                                              width: 2)))),
                              if (_errorMsg != null) ...[
                                const SizedBox(height: 8),
                                Text(_errorMsg!,
                                    style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 4)
                              ],
                              const SizedBox(height: 12),
                              SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFFB8C00),
                                          foregroundColor:
                                              const Color(0xFF000000),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12))),
                                      onPressed: _loading ? null : _verifyOTP,
                                      child: _loading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Color(0xFF000000)))
                                          : const Text("Verify & Login",
                                              style: TextStyle(
                                                  color: Color(0xFF000000),
                                                  fontSize: 16,
                                                  fontWeight:
                                                      FontWeight.bold)))),
                            ],
                          ])),
                    ]))))
      ]));
}

// ================================================================
// MAIN SHELL
// ================================================================
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  int _idx = 0;
  bool _loading = true;
  int _adminTaps = 0;
  DateTime? _lastAdminTap;

  UserProfile userProfile = UserProfile();
  SubscriptionInfo subscription = SubscriptionInfo();
  List<TripLedger> ledgers = [];
  List<Driver> drivers = [];
  List<Asset> fleet = [];
  List<MarketLoad> marketLoads = [];
  List<KredXApplication> kredxApps = [];

  // Post Load form state
  String _pVehicleType = "SS Tanker";
  final _pOriginCtrl = TextEditingController();
  final _pDestCtrl = TextEditingController();
  final _pFactoryOriginCtrl = TextEditingController();
  final _pFactoryDestCtrl = TextEditingController();
  final _pWeightCtrl = TextEditingController();
  final _pMaterialCtrl = TextEditingController(text: "Ethanol");
  final _pPriceCtrl = TextEditingController();
  String _pOriginState = '',
      _pDestState = '',
      _pOriginCity = '',
      _pDestCity = '',
      _pOriginPlaceId = '',
      _pDestPlaceId = '';

  // Find Load filters
  String _fOriginState = 'All', _fDestState = 'All';

  // Khata filters
  String _khataFilter = "All";
  String? _khataFilterVal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    try {
      if (p.getString('fm_profile') != null) {
        userProfile =
            UserProfile.fromJson(jsonDecode(p.getString('fm_profile')!));
      }
      if (p.getString('fm_sub') != null) {
        subscription =
            SubscriptionInfo.fromJson(jsonDecode(p.getString('fm_sub')!));
      }
      if (p.getString('fm_ledgers') != null) {
        ledgers = (jsonDecode(p.getString('fm_ledgers')!) as List)
            .map((e) => TripLedger.fromJson(e))
            .toList();
      }
      if (p.getString('fm_fleet') != null) {
        fleet = (jsonDecode(p.getString('fm_fleet')!) as List)
            .map((e) => Asset.fromJson(e))
            .toList();
      } else {
        fleet = List.generate(
            12,
            (i) => Asset(
                id: "V${i + 1}",
                number: "GJ-01-WT-${1000 + i}",
                type: "SS Tanker",
                payload: "30 Ton",
                tyreCount: 14,
                axleCount: 6,
                tyreSerials: List.filled(14, ""),
                batteries: [],
                docs: VehicleDocConfig.getRequiredDocs("SS Tanker")
                    .map((d) => FleetDoc(name: d))
                    .toList()));
      }
      if (p.getString('fm_drivers') != null) {
        drivers = (jsonDecode(p.getString('fm_drivers')!) as List)
            .map((e) => Driver.fromJson(e))
            .toList();
      }
      if (p.getString('fm_market') != null) {
        marketLoads = (jsonDecode(p.getString('fm_market')!) as List)
            .map((e) => MarketLoad.fromJson(e))
            .toList();
      } else {
        marketLoads = _demoMarketLoads();
      }
      if (p.getString('fm_kredx') != null) {
        kredxApps = (jsonDecode(p.getString('fm_kredx')!) as List)
            .map((e) => KredXApplication.fromJson(e))
            .toList();
      }
    } catch (_) {}
    // Inject demo data on first launch if nothing saved
    if (drivers.isEmpty && p.getString('fm_drivers') == null) {
      drivers = _demoDrivers();
    }
    if (ledgers.isEmpty && p.getString('fm_ledgers') == null) {
      ledgers = _demoLedgers();
    }
    setState(() => _loading = false);
    _checkPaymentAlerts();
    _startFirebaseSync();
  }

  StreamSubscription? _marketLoadSub;
  StreamSubscription? _ledgerSub;

  void _startFirebaseSync() {
    if (!FirebaseService.isReady || FirebaseService.currentUser == null) return;
    // Listen for market loads (shared across ALL users â€” the load board)
    _marketLoadSub?.cancel();
    _marketLoadSub = FirebaseFirestore.instance
        .collection('marketLoads')
        .where('status', whereIn: [
          '${BidStatus.pending.index}',
          '${BidStatus.booked.index}'
        ])
        .orderBy('postedDate', descending: true)
        .limit(60)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final remote =
              snap.docs.map((d) => _marketLoadFromFirestore(d.data())).toList();
          // Merge: keep local-only loads, update existing ones from remote
          setState(() {
            for (final r in remote) {
              final idx = marketLoads.indexWhere((l) => l.id == r.id);
              if (idx >= 0) {
                marketLoads[idx] = r;
              } else {
                marketLoads.insert(0, r);
              }
            }
          });
        }, onError: (_) {});
  }

  MarketLoad _marketLoadFromFirestore(Map<String, dynamic> d) => MarketLoad(
        id: d['id'] ?? '',
        route: d['route'] ?? '',
        details: d['details'] ?? '',
        vehicleType: d['vehicleType'] ?? '',
        targetPrice: (d['targetPrice'] as num? ?? 0).toDouble(),
        status: BidStatus.values[d['status'] as int? ?? 0],
        materialType: d['materialType'] ?? '',
        postedDate: d['postedDate'] ?? '',
        originCity: d['originCity'] ?? '',
        originState: d['originState'] ?? '',
        destCity: d['destCity'] ?? '',
        destState: d['destState'] ?? '',
        originFactory: d['originFactory'] ?? '',
        destFactory: d['destFactory'] ?? '',
        weightTons: (d['weightTons'] as num? ?? 0).toDouble(),
      );

  @override
  void dispose() {
    _marketLoadSub?.cancel();
    _ledgerSub?.cancel();
    super.dispose();
  }

  List<Driver> _demoDrivers() => [
        Driver(
            id: 'D1',
            name: 'Harpreet Singh',
            phone: '+91 98765 11001',
            balance: 12500,
            transactions: [
              DriverTx(
                  date: '15/4',
                  type: DriverTxType.salary,
                  amount: 22000,
                  note: 'April salary'),
              DriverTx(
                  date: '10/4',
                  type: DriverTxType.advance,
                  amount: -5000,
                  note: 'Advance')
            ],
            monthlySalary: 22000,
            aadharNum: '1234',
            dlNum: 'PB-0120230012345'),
        Driver(
            id: 'D2',
            name: 'Raju Yadav',
            phone: '+91 98765 22002',
            balance: -3000,
            transactions: [
              DriverTx(
                  date: '12/4',
                  type: DriverTxType.advance,
                  amount: -8000,
                  note: 'Advance taken'),
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 20000,
                  note: 'Salary')
            ],
            monthlySalary: 20000,
            aadharNum: '5678',
            dlNum: 'UP-6520220056789'),
        Driver(
            id: 'D3',
            name: 'Sukhvinder Gill',
            phone: '+91 98765 33003',
            balance: 18000,
            transactions: [
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 21000,
                  note: 'April salary')
            ],
            monthlySalary: 21000,
            dlNum: 'GJ-0120230099001'),
        Driver(
            id: 'D4',
            name: 'Mukesh Prajapati',
            phone: '+91 98765 44004',
            balance: 5000,
            transactions: [
              DriverTx(
                  date: '5/4',
                  type: DriverTxType.bonus,
                  amount: 3000,
                  note: 'On-time delivery bonus'),
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 19500,
                  note: 'Salary')
            ],
            monthlySalary: 19500),
        Driver(
            id: 'D5',
            name: 'Ramesh Devasi',
            phone: '+91 98765 55005',
            balance: 22000,
            transactions: [
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 22000,
                  note: 'April salary')
            ],
            monthlySalary: 22000,
            dlNum: 'GJ-0220230088776'),
        Driver(
            id: 'D6',
            name: 'Baldev Kumar',
            phone: '+91 98765 66006',
            balance: -1500,
            transactions: [
              DriverTx(
                  date: '8/4',
                  type: DriverTxType.penalty,
                  amount: -1500,
                  note: 'Late delivery penalty'),
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 20000,
                  note: 'Salary')
            ],
            monthlySalary: 20000),
        Driver(
            id: 'D7',
            name: 'Dinesh Parmar',
            phone: '+91 98765 77007',
            balance: 15000,
            transactions: [
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 21500,
                  note: 'Salary')
            ],
            monthlySalary: 21500,
            aadharNum: '9012',
            dlNum: 'GJ-1120230067432'),
        Driver(
            id: 'D8',
            name: 'Jagdish Solanki',
            phone: '+91 98765 88008',
            balance: 8500,
            transactions: [
              DriverTx(
                  date: '3/4',
                  type: DriverTxType.advance,
                  amount: -6000,
                  note: 'Medical advance'),
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 20000,
                  note: 'Salary')
            ],
            monthlySalary: 20000),
        Driver(
            id: 'D9',
            name: 'Vikram Rathod',
            phone: '+91 98765 99009',
            balance: 24000,
            transactions: [
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 24000,
                  note: 'Senior driver salary')
            ],
            monthlySalary: 24000,
            dlNum: 'GJ-0120220034567'),
        Driver(
            id: 'D10',
            name: 'Santosh Bind',
            phone: '+91 98765 10010',
            balance: 3000,
            transactions: [
              DriverTx(
                  date: '15/4',
                  type: DriverTxType.advance,
                  amount: -5000,
                  note: 'Advance'),
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 19000,
                  note: 'Salary')
            ],
            monthlySalary: 19000),
        Driver(
            id: 'D11',
            name: 'Ajay Verma',
            phone: '+91 98765 11011',
            balance: 16000,
            transactions: [
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 20000,
                  note: 'April salary')
            ],
            monthlySalary: 20000,
            aadharNum: '3456',
            dlNum: 'UP-4120220078901'),
        Driver(
            id: 'D12',
            name: 'Mohan Desai',
            phone: '+91 98765 12012',
            balance: 11000,
            transactions: [
              DriverTx(
                  date: '2/4',
                  type: DriverTxType.fuel,
                  amount: -2000,
                  note: 'Personal fuel draw'),
              DriverTx(
                  date: '1/4',
                  type: DriverTxType.salary,
                  amount: 21000,
                  note: 'Salary')
            ],
            monthlySalary: 21000,
            dlNum: 'GJ-0320230045612'),
      ];

  List<MarketLoad> _demoMarketLoads() => [
        MarketLoad(
            id: 'ML001',
            route: 'Hazira, Gujarat â†’ Panipat, Haryana',
            details: '28T | Ethanol',
            vehicleType: 'SS Tanker',
            targetPrice: 185000,
            status: BidStatus.pending,
            materialType: 'Ethanol',
            originCity: 'Hazira',
            originState: 'Gujarat',
            destCity: 'Panipat',
            destState: 'Haryana',
            originFactory: 'ONGC Hazira Plant',
            destFactory: 'IOCL Panipat Refinery',
            weightTons: 28,
            postedDate: '22/4/2026'),
        MarketLoad(
            id: 'ML002',
            route: 'Bharuch, Gujarat â†’ Pune, Maharashtra',
            details: '24T | Acetic Acid',
            vehicleType: 'MS Tanker',
            targetPrice: 98000,
            status: BidStatus.pending,
            materialType: 'Acetic Acid',
            originCity: 'Bharuch',
            originState: 'Gujarat',
            destCity: 'Pune',
            destState: 'Maharashtra',
            originFactory: 'Deepak Nitrite Bharuch',
            weightTons: 24,
            postedDate: '22/4/2026'),
        MarketLoad(
            id: 'ML003',
            route: 'Dahej, Gujarat â†’ Nagpur, Maharashtra',
            details: '20T | Chlorine Gas',
            vehicleType: 'SS Tanker',
            targetPrice: 115000,
            status: BidStatus.pending,
            materialType: 'Chlorine Gas',
            originCity: 'Dahej',
            originState: 'Gujarat',
            destCity: 'Nagpur',
            destState: 'Maharashtra',
            originFactory: 'Dahej Port Authority',
            weightTons: 20,
            postedDate: '21/4/2026'),
        MarketLoad(
            id: 'ML004',
            route: 'Mundra Port, Gujarat â†’ Delhi, NCR',
            details: '30T | Edible Oil',
            vehicleType: 'MS Tanker',
            targetPrice: 210000,
            status: BidStatus.pending,
            materialType: 'Edible Oil',
            originCity: 'Mundra Port',
            originState: 'Gujarat',
            destCity: 'Delhi',
            destState: 'Delhi',
            originFactory: 'Adani Wilmar Mundra',
            weightTons: 30,
            postedDate: '21/4/2026'),
        MarketLoad(
            id: 'ML005',
            route: 'Vapi, Gujarat â†’ Hyderabad, Telangana',
            details: '22T | Specialty Chemicals',
            vehicleType: 'SS Tanker',
            targetPrice: 155000,
            status: BidStatus.pending,
            materialType: 'Specialty Chemicals',
            originCity: 'Vapi',
            originState: 'Gujarat',
            destCity: 'Hyderabad',
            destState: 'Telangana',
            originFactory: 'Aarti Industries Vapi',
            weightTons: 22,
            postedDate: '20/4/2026'),
        MarketLoad(
            id: 'ML006',
            route: 'Kandla Port, Gujarat â†’ Lucknow, UP',
            details: '28T | Palm Oil',
            vehicleType: 'MS Tanker',
            targetPrice: 175000,
            status: BidStatus.pending,
            materialType: 'Palm Oil',
            originCity: 'Kandla Port',
            originState: 'Gujarat',
            destCity: 'Lucknow',
            destState: 'Uttar Pradesh',
            originFactory: 'Kandla Port Trust',
            weightTons: 28,
            postedDate: '20/4/2026'),
        MarketLoad(
            id: 'ML007',
            route: 'Ahmedabad, Gujarat â†’ Mumbai, Maharashtra',
            details: '20T | HSD/Diesel',
            vehicleType: 'SS Tanker',
            targetPrice: 68000,
            status: BidStatus.pending,
            materialType: 'HSD/Diesel',
            originCity: 'Ahmedabad',
            originState: 'Gujarat',
            destCity: 'Mumbai',
            destState: 'Maharashtra',
            weightTons: 20,
            postedDate: '19/4/2026'),
        MarketLoad(
            id: 'ML008',
            route: 'Vadodara, Gujarat â†’ Indore, MP',
            details: '18T | Refrigerant R-22',
            vehicleType: 'MS Tanker',
            targetPrice: 72000,
            status: BidStatus.pending,
            materialType: 'Refrigerant R-22',
            originCity: 'Vadodara',
            originState: 'Gujarat',
            destCity: 'Indore',
            destState: 'Madhya Pradesh',
            originFactory: 'Gujarat Fluorochemicals',
            weightTons: 18,
            postedDate: '19/4/2026'),
        // Cross-state loads for filter testing
        MarketLoad(
            id: 'ML009',
            route: 'Panipat, Haryana â†’ Mumbai, Maharashtra',
            details: '26T | Textile Yarn',
            vehicleType: 'Container',
            targetPrice: 145000,
            status: BidStatus.pending,
            materialType: 'Textile Yarn',
            originCity: 'Panipat',
            originState: 'Haryana',
            destCity: 'Mumbai',
            destState: 'Maharashtra',
            weightTons: 26,
            postedDate: '23/4/2026'),
        MarketLoad(
            id: 'ML010',
            route: 'Ludhiana, Punjab â†’ Chennai, Tamil Nadu',
            details: '22T | Auto Parts',
            vehicleType: 'Container',
            targetPrice: 195000,
            status: BidStatus.pending,
            materialType: 'Auto Parts',
            originCity: 'Ludhiana',
            originState: 'Punjab',
            destCity: 'Chennai',
            destState: 'Tamil Nadu',
            weightTons: 22,
            postedDate: '23/4/2026'),
        MarketLoad(
            id: 'ML011',
            route: 'Kolkata, West Bengal â†’ Delhi, NCR',
            details: '30T | Steel Coils',
            vehicleType: 'Trailer',
            targetPrice: 125000,
            status: BidStatus.pending,
            materialType: 'Steel Coils',
            originCity: 'Kolkata',
            originState: 'West Bengal',
            destCity: 'Delhi',
            destState: 'Delhi',
            weightTons: 30,
            postedDate: '22/4/2026'),
        MarketLoad(
            id: 'ML012',
            route: 'Hyderabad, Telangana â†’ Bangalore, Karnataka',
            details: '18T | Pharma Raw Material',
            vehicleType: 'Reefer',
            targetPrice: 62000,
            status: BidStatus.pending,
            materialType: 'Pharma Raw Material',
            originCity: 'Hyderabad',
            originState: 'Telangana',
            destCity: 'Bangalore',
            destState: 'Karnataka',
            weightTons: 18,
            postedDate: '22/4/2026'),
        MarketLoad(
            id: 'ML013',
            route: 'Jaipur, Rajasthan â†’ Kolkata, West Bengal',
            details: '24T | Marble Tiles',
            vehicleType: 'Open Truck',
            targetPrice: 118000,
            status: BidStatus.pending,
            materialType: 'Marble Tiles',
            originCity: 'Jaipur',
            originState: 'Rajasthan',
            destCity: 'Kolkata',
            destState: 'West Bengal',
            weightTons: 24,
            postedDate: '21/4/2026'),
        MarketLoad(
            id: 'ML014',
            route: 'Pune, Maharashtra â†’ Amritsar, Punjab',
            details: '20T | Tractor Parts',
            vehicleType: 'Container',
            targetPrice: 132000,
            status: BidStatus.pending,
            materialType: 'Tractor Parts',
            originCity: 'Pune',
            originState: 'Maharashtra',
            destCity: 'Amritsar',
            destState: 'Punjab',
            weightTons: 20,
            postedDate: '21/4/2026'),
        MarketLoad(
            id: 'ML015',
            route: 'Haldia Port, West Bengal â†’ Indore, MP',
            details: '28T | Crude Palm Oil',
            vehicleType: 'MS Tanker',
            targetPrice: 155000,
            status: BidStatus.pending,
            materialType: 'Crude Palm Oil',
            originCity: 'Haldia Port',
            originState: 'West Bengal',
            destCity: 'Indore',
            destState: 'Madhya Pradesh',
            weightTons: 28,
            postedDate: '20/4/2026'),
        MarketLoad(
            id: 'ML016',
            route: 'Bathinda, Punjab â†’ Daman, Daman & Diu',
            details: '26T | Fertilizers',
            vehicleType: 'Open Truck',
            targetPrice: 138000,
            status: BidStatus.pending,
            materialType: 'Fertilizers',
            originCity: 'Bathinda',
            originState: 'Punjab',
            destCity: 'Daman',
            destState: 'Daman & Diu',
            weightTons: 26,
            postedDate: '20/4/2026'),
        MarketLoad(
            id: 'ML017',
            route: 'Raipur, Chhattisgarh â†’ Surat, Gujarat',
            details: '30T | Iron Ore',
            vehicleType: 'Open Truck',
            targetPrice: 108000,
            status: BidStatus.pending,
            materialType: 'Iron Ore',
            originCity: 'Raipur',
            originState: 'Chhattisgarh',
            destCity: 'Surat',
            destState: 'Gujarat',
            weightTons: 30,
            postedDate: '19/4/2026'),
        MarketLoad(
            id: 'ML018',
            route: 'Bhubaneswar, Odisha â†’ Nagpur, Maharashtra',
            details: '25T | Coal',
            vehicleType: 'Open Truck',
            targetPrice: 92000,
            status: BidStatus.pending,
            materialType: 'Coal',
            originCity: 'Bhubaneswar',
            originState: 'Odisha',
            destCity: 'Nagpur',
            destState: 'Maharashtra',
            weightTons: 25,
            postedDate: '19/4/2026'),
        MarketLoad(
            id: 'ML019',
            route: 'Kochi, Kerala â†’ Hyderabad, Telangana',
            details: '20T | Cashew Nuts',
            vehicleType: 'Container',
            targetPrice: 88000,
            status: BidStatus.pending,
            materialType: 'Cashew Nuts',
            originCity: 'Kochi',
            originState: 'Kerala',
            destCity: 'Hyderabad',
            destState: 'Telangana',
            weightTons: 20,
            postedDate: '18/4/2026'),
        MarketLoad(
            id: 'ML020',
            route: 'Guwahati, Assam â†’ Delhi, NCR',
            details: '18T | Tea',
            vehicleType: 'Container',
            targetPrice: 175000,
            status: BidStatus.pending,
            materialType: 'Tea',
            originCity: 'Guwahati',
            originState: 'Assam',
            destCity: 'Delhi',
            destState: 'Delhi',
            weightTons: 18,
            postedDate: '18/4/2026'),
      ];

  List<TripLedger> _demoLedgers() => [
        TripLedger(
            id: 'TRP10001',
            date: '1/4/2026',
            partyName: 'Reliance Industries Ltd',
            vehicleNo: 'GJ-01-WT-1000',
            route: 'Hazira, Gujarat â†’ Panipat, Haryana',
            ownership: VehicleOwnership.self,
            materialName: 'Ethanol',
            freightBilled: 185000,
            paymentReceived: 100000,
            diesel: 42000,
            toll: 12800,
            driverExp: 8500,
            loadingPoint: 'Hazira',
            unloadingPoint: 'Panipat',
            loadingState: 'Gujarat',
            unloadingState: 'Haryana',
            eWayBillNo: 'EWB2410100001',
            paymentTermsDays: 30,
            distanceKm: 1380,
            driverName: 'Harpreet Singh',
            weightTons: 28,
            weightUnit: 'MT',
            gstType: GstType.igst,
            gstRate: 5.0),
        TripLedger(
            id: 'TRP10002',
            date: '3/4/2026',
            partyName: 'IOCL Mathura Refinery',
            vehicleNo: 'GJ-01-WT-1001',
            route: 'Kandla Port, Gujarat â†’ Mathura, UP',
            ownership: VehicleOwnership.self,
            materialName: 'Crude Chemical',
            freightBilled: 210000,
            paymentReceived: 210000,
            diesel: 38500,
            toll: 11200,
            driverExp: 9000,
            loadingPoint: 'Kandla Port',
            unloadingPoint: 'Mathura',
            loadingState: 'Gujarat',
            unloadingState: 'Uttar Pradesh',
            eWayBillNo: 'EWB2410100002',
            paymentTermsDays: 45,
            distanceKm: 1270,
            driverName: 'Raju Yadav',
            weightTons: 30,
            weightUnit: 'MT'),
        TripLedger(
            id: 'TRP10003',
            date: '5/4/2026',
            partyName: 'Deepak Nitrite Ltd',
            vehicleNo: 'GJ-01-WT-1002',
            route: 'Dahej, Gujarat â†’ Pune, Maharashtra',
            ownership: VehicleOwnership.self,
            materialName: 'Nitric Acid',
            freightBilled: 95000,
            paymentReceived: 50000,
            diesel: 22000,
            toll: 6400,
            driverExp: 5500,
            loadingPoint: 'Dahej',
            unloadingPoint: 'Pune',
            loadingState: 'Gujarat',
            unloadingState: 'Maharashtra',
            eWayBillNo: 'EWB2410100003',
            paymentTermsDays: 30,
            distanceKm: 590,
            driverName: 'Sukhvinder Gill',
            weightTons: 24,
            weightUnit: 'MT',
            gstType: GstType.cgstSgst,
            gstRate: 12.0),
        TripLedger(
            id: 'TRP10004',
            date: '7/4/2026',
            partyName: 'Tata Chemicals Mithapur',
            vehicleNo: 'GJ-01-WT-1003',
            route: 'Bharuch, Gujarat â†’ Nagpur, Maharashtra',
            ownership: VehicleOwnership.market,
            materialName: 'Soda Ash',
            freightBilled: 125000,
            paymentReceived: 125000,
            marketTruckFreight: 98000,
            marketAdvancePaid: 50000,
            loadingPoint: 'Bharuch',
            unloadingPoint: 'Nagpur',
            loadingState: 'Gujarat',
            unloadingState: 'Maharashtra',
            eWayBillNo: 'EWB2410100004',
            paymentTermsDays: 15,
            distanceKm: 720),
        TripLedger(
            id: 'TRP10005',
            date: '9/4/2026',
            partyName: 'BPCL Mahul Terminal',
            vehicleNo: 'GJ-01-WT-1004',
            route: 'Ahmedabad, Gujarat â†’ Mumbai, Maharashtra',
            ownership: VehicleOwnership.self,
            materialName: 'HSD/Diesel',
            freightBilled: 78000,
            paymentReceived: 78000,
            diesel: 18500,
            toll: 5400,
            driverExp: 4200,
            loadingPoint: 'Ahmedabad',
            unloadingPoint: 'Mumbai',
            loadingState: 'Gujarat',
            unloadingState: 'Maharashtra',
            eWayBillNo: 'EWB2410100005',
            paymentTermsDays: 30,
            distanceKm: 527,
            driverName: 'Mukesh Prajapati',
            weightTons: 26,
            weightUnit: 'MT'),
        TripLedger(
            id: 'TRP10006',
            date: '11/4/2026',
            partyName: 'Gujarat Fluorochemicals',
            vehicleNo: 'GJ-01-WT-1005',
            route: 'Vadodara, Gujarat â†’ Indore, MP',
            ownership: VehicleOwnership.self,
            materialName: 'Refrigerant Gas R-22',
            freightBilled: 68000,
            paymentReceived: 35000,
            diesel: 16800,
            toll: 4900,
            driverExp: 3800,
            loadingPoint: 'Vadodara',
            unloadingPoint: 'Indore',
            loadingState: 'Gujarat',
            unloadingState: 'Madhya Pradesh',
            eWayBillNo: 'EWB2410100006',
            paymentTermsDays: 30,
            distanceKm: 430,
            driverName: 'Ramesh Devasi',
            weightTons: 20,
            weightUnit: 'MT'),
        TripLedger(
            id: 'TRP10007',
            date: '13/4/2026',
            partyName: 'Aarti Industries Vapi',
            vehicleNo: 'GJ-01-WT-1006',
            route: 'Vapi, Gujarat â†’ Hyderabad, Telangana',
            ownership: VehicleOwnership.market,
            materialName: 'Specialty Chemicals',
            freightBilled: 155000,
            paymentReceived: 80000,
            marketTruckFreight: 122000,
            marketAdvancePaid: 60000,
            loadingPoint: 'Vapi',
            unloadingPoint: 'Hyderabad',
            loadingState: 'Gujarat',
            unloadingState: 'Telangana',
            eWayBillNo: 'EWB2410100007',
            paymentTermsDays: 45,
            distanceKm: 1310),
        TripLedger(
            id: 'TRP10008',
            date: '15/4/2026',
            partyName: 'Nayara Energy Vadinar',
            vehicleNo: 'GJ-01-WT-1007',
            route: 'Jamnagar, Gujarat â†’ Delhi, NCR',
            ownership: VehicleOwnership.self,
            materialName: 'Motor Spirit/Petrol',
            freightBilled: 235000,
            paymentReceived: 0,
            diesel: 48000,
            toll: 14500,
            driverExp: 10500,
            loadingPoint: 'Jamnagar',
            unloadingPoint: 'Delhi',
            loadingState: 'Gujarat',
            unloadingState: 'Delhi',
            eWayBillNo: 'EWB2410100008',
            paymentTermsDays: 30,
            distanceKm: 1125,
            driverName: 'Jagdish Solanki',
            weightTons: 30,
            weightUnit: 'MT',
            gstType: GstType.igst,
            gstRate: 5.0),
        TripLedger(
            id: 'TRP10009',
            date: '18/4/2026',
            partyName: 'UPL Ltd Ankleshwar',
            vehicleNo: 'GJ-01-WT-1008',
            route: 'Ankleshwar, Gujarat â†’ Bangalore, Karnataka',
            ownership: VehicleOwnership.self,
            materialName: 'Agrochemicals',
            freightBilled: 172000,
            paymentReceived: 90000,
            diesel: 36500,
            toll: 10800,
            driverExp: 8200,
            loadingPoint: 'Ankleshwar',
            unloadingPoint: 'Bangalore',
            loadingState: 'Gujarat',
            unloadingState: 'Karnataka',
            eWayBillNo: 'EWB2410100009',
            paymentTermsDays: 45,
            distanceKm: 1445,
            driverName: 'Vikram Rathod',
            weightTons: 25,
            weightUnit: 'MT'),
        TripLedger(
            id: 'TRP10010',
            date: '20/4/2026',
            partyName: 'Adani Wilmar Mundra',
            vehicleNo: 'GJ-01-WT-1009',
            route: 'Mundra Port, Gujarat â†’ Lucknow, UP',
            ownership: VehicleOwnership.self,
            materialName: 'Edible Oil',
            freightBilled: 142000,
            paymentReceived: 142000,
            diesel: 32000,
            toll: 9600,
            driverExp: 7500,
            loadingPoint: 'Mundra Port',
            unloadingPoint: 'Lucknow',
            loadingState: 'Gujarat',
            unloadingState: 'Uttar Pradesh',
            eWayBillNo: 'EWB2410100010',
            paymentTermsDays: 30,
            distanceKm: 1370,
            driverName: 'Ajay Verma',
            weightTons: 28,
            weightUnit: 'MT'),
      ];

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('fm_profile', jsonEncode(userProfile.toJson()));
    await p.setString('fm_sub', jsonEncode(subscription.toJson()));
    await p.setString(
        'fm_ledgers', jsonEncode(ledgers.map((e) => e.toJson()).toList()));
    await p.setString(
        'fm_fleet', jsonEncode(fleet.map((e) => e.toJson()).toList()));
    await p.setString(
        'fm_drivers', jsonEncode(drivers.map((e) => e.toJson()).toList()));
    await p.setString(
        'fm_market', jsonEncode(marketLoads.map((e) => e.toJson()).toList()));
    await p.setString(
        'fm_kredx', jsonEncode(kredxApps.map((e) => e.toJson()).toList()));
  }

  // Only alert when â‰¤5 days away (not overdue yet)
  void _checkPaymentAlerts() {
    final dueSoon =
        ledgers.where((l) => l.isDueSoon && !l.isPaymentOverdue).toList();
    if (dueSoon.isEmpty) return;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      showDialog(
          context: context,
          builder: (c) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Row(children: [
                  Icon(Icons.schedule, color: Colors.orange[700]),
                  const SizedBox(width: 10),
                  const Text("Payment Due Soon",
                      style: TextStyle(fontWeight: FontWeight.w900))
                ]),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          "ðŸŸ¡ ${dueSoon.length} payment${dueSoon.length > 1 ? 's' : ''} due within ${AppConfig.paymentAlertDays} days",
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.orange)),
                      const SizedBox(height: 8),
                      ...dueSoon.take(4).map((l) {
                        final d = l.paymentDueDate;
                        return Text(
                            "â€¢ ${l.partyName} â€” â‚¹${l.partyPending.toStringAsFixed(0)} (due ${d != null ? '${d.day}/${d.month}' : ''})",
                            style: const TextStyle(fontSize: 13));
                      }),
                    ]),
                actions: [
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF8E1)),
                      onPressed: () {
                        Navigator.pop(c);
                        setState(() => _idx = 3);
                      },
                      child: const Text("View Ledger",
                          style: TextStyle(color: Color(0xFF000000)))),
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Dismiss"))
                ],
              ));
    });
  }

  // Hidden admin: tap title 7x in 3 seconds
  void _handleAdminTap() {
    final now = DateTime.now();
    if (_lastAdminTap == null ||
        now.difference(_lastAdminTap!).inMilliseconds >
            AppConfig.adminTapWindowMs) {
      _adminTaps = 1;
    } else {
      _adminTaps++;
    }
    _lastAdminTap = now;
    if (_adminTaps >= AppConfig.adminTapCount) {
      _adminTaps = 0;
      _promptAdminPin();
    }
  }

  // â”€â”€ REAL OTP via Firebase Phone Auth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void sendOTPToDriver(String phone, Function(bool verified) onResult) {
    String verId = '';
    final otpCtrl = TextEditingController();
    bool codeSent = false, loading = true;
    String err = '';
    final fmtPhone = phone.startsWith('+')
        ? phone
        : '+91${phone.replaceAll(RegExp(r'\D'), '')}';

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => StatefulBuilder(builder: (c2, ss) {
              if (loading && !codeSent && err.isEmpty) {
                FirebaseService.sendOTP(
                    phone: fmtPhone,
                    onCodeSent: (vid) => ss(() {
                          verId = vid;
                          codeSent = true;
                          loading = false;
                        }),
                    onError: (e) => ss(() {
                          err = e;
                          loading = false;
                        }));
              }
              return AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                title: const Row(children: [
                  Icon(Icons.sms, color: Color(0xFF000000)),
                  SizedBox(width: 8),
                  Text("OTP Verification",
                      style: TextStyle(fontWeight: FontWeight.w800))
                ]),
                content: loading
                    ? const SizedBox(
                        height: 70,
                        child: Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text("Sending OTP to number...",
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 13))
                            ])))
                    : err.isNotEmpty
                        ? Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 44),
                            const SizedBox(height: 10),
                            Text(err,
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            const Text(
                                "Enable Phone Auth in Firebase Console â†’ Authentication â†’ Sign-in providers",
                                style:
                                    TextStyle(fontSize: 11, color: Colors.grey),
                                textAlign: TextAlign.center),
                          ])
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Row(children: [
                                  const Icon(Icons.check_circle,
                                      color: Colors.green, size: 16),
                                  const SizedBox(width: 8),
                                  Flexible(
                                      child: Text("OTP sent to $fmtPhone",
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w700)))
                                ])),
                            const SizedBox(height: 14),
                            TextField(
                                controller: otpCtrl,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                autofocus: true,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 8),
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                    labelText: "Enter 6-digit OTP",
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    counterText: '')),
                          ]),
                actions: [
                  TextButton(
                      onPressed: () {
                        Navigator.pop(c);
                        onResult(false);
                      },
                      child: const Text("Cancel")),
                  if (codeSent)
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF8E1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        icon: const Icon(Icons.verified,
                            color: Color(0xFF000000), size: 16),
                        label: const Text("Verify",
                            style: TextStyle(
                                color: Color(0xFF000000),
                                fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          if (otpCtrl.text.length < 6) return;
                          ss(() => loading = true);
                          final ok = await FirebaseService.verifyOTP(
                              verificationId: verId, otp: otpCtrl.text);
                          Navigator.pop(c);
                          onResult(ok);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              backgroundColor: ok ? Colors.green : Colors.red,
                              behavior: SnackBarBehavior.floating,
                              content: Text(ok
                                  ? "âœ… Phone verified!"
                                  : "âŒ Incorrect OTP. Try again.")));
                        }),
                ],
              );
            }));
  }

  void _promptAdminPin() {
    final ctrl = TextEditingController();
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: const Row(children: [
                Icon(Icons.security, color: Color(0xFF000000)),
                SizedBox(width: 10),
                Text("Developer Access",
                    style: TextStyle(fontWeight: FontWeight.bold))
              ]),
              content: TextField(
                  style: const TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  controller: ctrl,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: "Master PIN",
                      filled: true,
                      fillColor: const Color(0xFFFFF8E1),
                      labelStyle: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                      floatingLabelStyle: const TextStyle(
                          color: Color(0xFFFB8C00),
                          fontWeight: FontWeight.w800,
                          fontSize: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFFB8C00))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFFB8C00))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFFB8C00), width: 2)))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text("Cancel")),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF8E1)),
                    onPressed: () {
                      if (AppConfig.validatePin(ctrl.text)) {
                        Navigator.pop(c);
                        if (!mounted) return;
                        Future.microtask(() {
                          if (!mounted) return;
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => AdvancedAdminScreen(
                                        ledgers: ledgers,
                                        fleet: fleet,
                                        drivers: drivers,
                                        kredxApps: kredxApps,
                                        userProfile: userProfile,
                                        subscription: subscription,
                                        onFactoryReset: () async {
                                          final p = await SharedPreferences
                                              .getInstance();
                                          await p.clear();
                                          if (!mounted) return;
                                          setState(() {
                                            ledgers.clear();
                                            fleet.clear();
                                            drivers.clear();
                                            marketLoads.clear();
                                            kredxApps.clear();
                                            subscription = SubscriptionInfo();
                                          });
                                          _load();
                                        },
                                        onUpdate: () {
                                          if (mounted) setState(() {});
                                          _save();
                                        },
                                      )));
                        });
                      } else {
                        Navigator.pop(c);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Invalid PIN"),
                                backgroundColor: Colors.red));
                      }
                    },
                    child: const Text("Enter",
                        style: TextStyle(color: Color(0xFF000000)))),
              ],
            ));
  }

  void _upgradeBanner(String feat) => showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
            padding: const EdgeInsets.all(28),
            decoration: const BoxDecoration(
                color: Color(0xFFFBF7F0),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.workspace_premium,
                      color: Colors.amber, size: 36)),
              const SizedBox(height: 16),
              Text("Unlock $feat",
                  style: const TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text("Upgrade to access $feat.",
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0x601C1917), fontSize: 14)),
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[700],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      onPressed: () {
                        Navigator.pop(context);
                        _openSub();
                      },
                      child: const Text("View Plans & Upgrade",
                          style: TextStyle(
                              color: Color(0xFF000000),
                              fontWeight: FontWeight.bold,
                              fontSize: 16)))),
              const SizedBox(height: 12),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Not now",
                      style: TextStyle(color: Color(0x381C1917)))),
            ]),
          ));

  void _openSub() => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SubscriptionScreen(
              current: subscription,
              onUpgrade: (t) {
                setState(() {
                  subscription.tier = t;
                  final exp = DateTime.now().add(const Duration(days: 30));
                  subscription.expiryDate =
                      "${exp.day}/${exp.month}/${exp.year}";
                });
                _save();
              })));

  // â”€â”€ DASHBOARD â”€â”€
  Widget _buildDash() {
    double rev = ledgers.fold<double>(0, (s, l) => s + l.freightBilled);
    double exp = ledgers.fold(
        0,
        (s, l) =>
            s +
            (l.ownership == VehicleOwnership.self
                ? l.selfExpenses
                : l.marketTruckFreight));
    double profit = ledgers.fold<double>(0, (s, l) => s + l.tripProfit);
    double pending = ledgers.fold<double>(
        0, (s, l) => s + (l.partyPending > 0 ? l.partyPending : 0));
    int dueSoonCount =
        ledgers.where((l) => l.isDueSoon && !l.isPaymentOverdue).length;
    int activeN = ledgers.where((l) => l.partyPending > 0).length;

    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              "Good ${DateTime.now().hour < 12 ? 'Morning' : DateTime.now().hour < 17 ? 'Afternoon' : 'Evening'} ðŸ‘‹",
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF000000),
                  fontWeight: FontWeight.w500)),
          const Text("Operations Hub",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF000000),
                  height: 1.2)),
        ]),
        GestureDetector(
            onTap: _openSub,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    subscription.tierColor,
                    subscription.tierColor.withOpacity(0.75)
                  ]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: subscription.tierColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4))
                  ]),
              child: Row(children: [
                const Icon(Icons.workspace_premium,
                    size: 13, color: Color(0xFF000000)),
                const SizedBox(width: 5),
                Text(subscription.tierName,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF000000)))
              ]),
            )),
      ]),
      const SizedBox(height: 20),
      if (dueSoonCount > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!)),
          child: Row(children: [
            Icon(Icons.schedule, color: Colors.orange[700], size: 18),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    "$dueSoonCount payment${dueSoonCount > 1 ? 's' : ''} due within ${AppConfig.paymentAlertDays} days",
                    style: TextStyle(
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w700,
                        fontSize: 13))),
            GestureDetector(
                onTap: () => setState(() => _idx = 3),
                child: Text("View â†’",
                    style: TextStyle(
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w900,
                        fontSize: 12)))
          ]),
        ),
      GestureDetector(
        onTap: _showExpenses,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [
                Color(0xFFFFF8E1),
                Color(0xFFFB8C00),
                Color(0xFF0EA5E9)
              ], stops: [
                0.0,
                0.5,
                1.0
              ], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFB8C00).withOpacity(0.45),
                    blurRadius: 32,
                    offset: const Offset(0, 14))
              ]),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Total Revenue",
                  style: TextStyle(
                      color: Color(0x601C1917),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFF000000).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Color(0x241C1917))),
                  child: const Row(children: [
                    Icon(Icons.bar_chart, color: Color(0x701C1917), size: 12),
                    SizedBox(width: 4),
                    Text("Tap for Breakdown",
                        style: TextStyle(
                            color: Color(0x701C1917),
                            fontSize: 10,
                            fontWeight: FontWeight.bold))
                  ])),
            ]),
            const SizedBox(height: 10),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("â‚¹${rev.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF000000))),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              _heroStat(
                                  "Profit",
                                  "â‚¹${profit >= 100000 ? '${(profit / 100000).toStringAsFixed(1)}L' : profit.toStringAsFixed(0)}",
                                  const Color(0xFFFB8C00)),
                              const SizedBox(width: 14),
                              _heroStat(
                                  "Expenses",
                                  "â‚¹${exp >= 100000 ? '${(exp / 100000).toStringAsFixed(1)}L' : exp.toStringAsFixed(0)}",
                                  const Color(0xFFE53E3E))
                            ])),
                      ]),
                  GestureDetector(
                      onTap: () => showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                title: const Text("Financial Breakdown",
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900)),
                                content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ...[
                                        (
                                          "Total Revenue",
                                          _fmtAmt(rev),
                                          Colors.green
                                        ),
                                        (
                                          "Total Expenses",
                                          _fmtAmt(exp),
                                          Colors.red
                                        ),
                                        (
                                          "Net Profit",
                                          _fmtAmt(profit),
                                          profit >= 0
                                              ? Colors.green
                                              : Colors.red
                                        ),
                                      ].map((r) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(r.$1,
                                                    style: const TextStyle(
                                                        color: Color(
                                                            0xFF8FBC8F),
                                                        fontSize: 13)),
                                                Text(r.$2,
                                                    style: TextStyle(
                                                        color: r.$3,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 13))
                                              ]))),
                                      const Divider(),
                                      ...[
                                        (
                                          "Diesel",
                                          _fmtAmt(ledgers.fold<double>(
                                              0, (s, l) => s + l.diesel)),
                                          Colors.orange
                                        ),
                                        (
                                          "Toll",
                                          _fmtAmt(ledgers.fold<double>(
                                              0, (s, l) => s + l.toll)),
                                          Colors.blue
                                        ),
                                        (
                                          "Driver Exp",
                                          _fmtAmt(ledgers.fold<double>(
                                              0, (s, l) => s + l.driverExp)),
                                          Colors.purple
                                        ),
                                        (
                                          "Margin",
                                          rev > 0
                                              ? "${(profit / rev * 100).toStringAsFixed(1)}%"
                                              : "0%",
                                          Colors.teal
                                        ),
                                      ].map((r) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(r.$1,
                                                    style: const TextStyle(
                                                        color: Color(
                                                            0xFF8FBC8F),
                                                        fontSize: 13)),
                                                Text(r.$2,
                                                    style: TextStyle(
                                                        color: r.$3,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 13))
                                              ]))),
                                    ]),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Close"))
                                ],
                              )),
                      child: SizedBox(
                          height: 90,
                          width: 90,
                          child: CustomPaint(
                              painter: NativePieChartPainter(
                                  revenue: rev, expense: exp)))),
                ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: GestureDetector(
                onTap: () {
                  final active =
                      ledgers.where((l) => l.partyPending > 0).toList();
                  showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => DraggableScrollableSheet(
                          initialChildSize: 0.7,
                          maxChildSize: 0.95,
                          minChildSize: 0.4,
                          builder: (_, sc) => Container(
                                decoration: const BoxDecoration(
                                    color: Color(0xFFFBF7F0),
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(24))),
                                child: Column(children: [
                                  Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      width: 40,
                                      height: 4,
                                      decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                          borderRadius:
                                              BorderRadius.circular(4))),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 8),
                                      child: Row(children: [
                                        const Icon(Icons.local_shipping,
                                            color: Color(0xFF000000)),
                                        const SizedBox(width: 10),
                                        Text(
                                            "Active Movements (${active.length})",
                                            style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w900,
                                                color:
                                                    Color(0xFF000000))),
                                      ])),
                                  const Divider(height: 1),
                                  Expanded(
                                      child: active.isEmpty
                                          ? const Center(
                                              child: Text(
                                                  "No active trips right now",
                                                  style: TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 15)))
                                          : ListView.separated(
                                              controller: sc,
                                              padding: const EdgeInsets.all(16),
                                              itemCount: active.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 10),
                                              itemBuilder: (_, i) {
                                                final l = active[i];
                                                return Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            14),
                                                    decoration: BoxDecoration(
                                                        color: const Color(
                                                            0xFFF2EDE4),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(16),
                                                        border: Border.all(
                                                            color: const Color(
                                                                0xFF3D5A47))),
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              children: [
                                                                Expanded(
                                                                    child: Text(
                                                                        l
                                                                            .partyName,
                                                                        style: const TextStyle(
                                                                            fontWeight: FontWeight
                                                                                .w900,
                                                                            fontSize:
                                                                                14,
                                                                            color: Color(
                                                                                0xFFF2EDE4)),
                                                                        overflow:
                                                                            TextOverflow.ellipsis)),
                                                                Container(
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            8,
                                                                        vertical:
                                                                            3),
                                                                    decoration: BoxDecoration(
                                                                        color: l.isPaymentOverdue
                                                                            ? Colors.red[
                                                                                50]
                                                                            : Colors.blue[
                                                                                50],
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                                8)),
                                                                    child: Text(
                                                                        l.isPaymentOverdue
                                                                            ? "OVERDUE"
                                                                            : "EN ROUTE",
                                                                        style: TextStyle(
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight: FontWeight.bold,
                                                                            color: l.isPaymentOverdue ? Colors.red : Colors.blue))),
                                                              ]),
                                                          const SizedBox(
                                                              height: 6),
                                                          Row(children: [
                                                            const Icon(
                                                                Icons.route,
                                                                size: 14,
                                                                color: Colors
                                                                    .grey),
                                                            const SizedBox(
                                                                width: 4),
                                                            Expanded(
                                                                child: Text(
                                                                    l.route,
                                                                    style: const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: Colors
                                                                            .grey),
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis))
                                                          ]),
                                                          const SizedBox(
                                                              height: 4),
                                                          Row(children: [
                                                            const Icon(
                                                                Icons
                                                                    .local_shipping,
                                                                size: 14,
                                                                color: Colors
                                                                    .indigo),
                                                            const SizedBox(
                                                                width: 4),
                                                            Text(l.vehicleNo,
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .indigo,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700)),
                                                            if (l.driverName !=
                                                                null) ...[
                                                              const SizedBox(
                                                                  width: 10),
                                                              const Icon(
                                                                  Icons.person,
                                                                  size: 14,
                                                                  color: Colors
                                                                      .grey),
                                                              const SizedBox(
                                                                  width: 4),
                                                              Text(
                                                                  l.driverName!,
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      color: Colors
                                                                          .grey),
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis)
                                                            ],
                                                          ]),
                                                          const SizedBox(
                                                              height: 8),
                                                          Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              children: [
                                                                Text(
                                                                    "Pending: â‚¹${l.partyPending.toStringAsFixed(0)}",
                                                                    style: const TextStyle(
                                                                        color: Colors
                                                                            .red,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w800,
                                                                        fontSize:
                                                                            13)),
                                                                Text(l.date,
                                                                    style: const TextStyle(
                                                                        color: Colors
                                                                            .grey,
                                                                        fontSize:
                                                                            11)),
                                                              ]),
                                                        ]));
                                              })),
                                ]),
                              )));
                },
                child: _statTile("Active Trips", "$activeN",
                    Icons.local_shipping, Colors.blue))),
        const SizedBox(width: 12),
        Expanded(
            child: _statTile(
                "Pending â‚¹",
                "â‚¹${(pending / 1000).toStringAsFixed(0)}K",
                Icons.hourglass_top,
                Colors.orange)),
        const SizedBox(width: 12),
        Expanded(
            child: _statTile("Fleet", "${fleet.length}", Icons.directions_car,
                Colors.purple)),
      ]),
      const SizedBox(height: 24),
      Row(children: [
        Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
                color: const Color(0xFFFB8C00),
                borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        const Text("Quick Actions",
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF000000),
                letterSpacing: 0.3))
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: _actBtn2(Icons.add_box_rounded, "New Trip",
                const Color(0xFFFB8C00), () => _showNewEntry())),
        const SizedBox(width: 10),
        Expanded(
            child: _actBtn2(
                Icons.gps_fixed_rounded, "Track", const Color(0xFFFB8C00), () {
          if (!subscription.canUseGPS) {
            _upgradeBanner("Live GPS Tracking");
            return;
          }
          _trackDialog();
        })),
        const SizedBox(width: 10),
        Expanded(
            child: _actBtn2(
                Icons.file_upload_outlined,
                "Export",
                const Color(0xFFFB8C00),
                () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TallyExportScreen(
                            ledgers: ledgers,
                            drivers: drivers,
                            userProfile: userProfile))))),
        const SizedBox(width: 10),
        Expanded(
            child: _actBtn2(
                Icons.account_balance_rounded, "KredX", const Color(0xFFFB8C00),
                () {
          if (!subscription.canUseKredX) {
            _upgradeBanner("KredX Invoice Financing");
            return;
          }
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => KredXScreen(
                      ledgers: ledgers,
                      kredxApps: kredxApps,
                      onApply: (a) {
                        setState(() => kredxApps.insert(0, a));
                        _save();
                      },
                      onUpdate: () {
                        setState(() {});
                        _save();
                      })));
        })),
      ]),
      const SizedBox(height: 20),
      const SizedBox(height: 16),
      if (ledgers.isNotEmpty) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                    color: const Color(0xFFFB8C00),
                    borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            const Text("Recent Trips",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF000000),
                    letterSpacing: 0.3))
          ]),
          GestureDetector(
              onTap: () => setState(() => _idx = 3),
              child: const Text("See All â†’",
                  style: TextStyle(
                      color: Colors.blueAccent, fontWeight: FontWeight.w700)))
        ]),
        const SizedBox(height: 12),
        ...ledgers.take(3).map(_miniCard),
      ],
    ]);
  }

  Widget _chip(IconData icon, String label, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: c.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withOpacity(0.25))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: c, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis)
        ]),
      );
  Widget _statTile(String label, String val, IconData icon, Color c) =>
      Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: c, width: 3)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: c.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c, size: 18),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(val,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF000000))),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ]));
  Widget _actBtn(IconData icon, String label, Color c, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [c.withOpacity(0.12), c.withOpacity(0.06)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.withOpacity(0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: c, size: 18),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF000000)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ));
  Widget _actBtn2(
          IconData icon, String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [color.withOpacity(0.15), color.withOpacity(0.08)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
  Widget _navIcon(IconData icon, int tabIdx) => Icon(icon,
      size: 24,
      color:
          _idx == tabIdx ? const Color(0xFFFB8C00) : const Color(0xFF000000));
  String _fmtAmt(double v) => v >= 100000
      ? 'â‚¹${(v / 100000).toStringAsFixed(1)}L'
      : v >= 1000
          ? 'â‚¹${(v / 1000).toStringAsFixed(1)}K'
          : 'â‚¹${v.toStringAsFixed(0)}';

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF000000),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)),
                const SizedBox(height: 2),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: color))),
              ])),
        ]),
      );
  Widget _heroStat(String label, String value, Color c) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style:
                TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w900)),
        Text(label,
            style: const TextStyle(
                color: Color(0x381C1917),
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ]);

  Widget _miniCard(TripLedger l) {
    final c = l.isPaymentOverdue
        ? const Color(0xFFE53E3E)
        : l.isDueSoon
            ? const Color(0xFFFB8C00)
            : l.partyPending <= 0
                ? const Color(0xFFFB8C00)
                : const Color(0xFFFB8C00);
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC4D4C9)),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF000000).withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
            BoxShadow(
                color: c.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(children: [
          Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [c, c.withOpacity(0.5)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter),
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(l.partyName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF000000)),
                    overflow: TextOverflow.ellipsis),
                Text("${l.vehicleNo} â€¢ ${l.route}",
                    style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: c.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                        l.isPaymentOverdue
                            ? "OVERDUE"
                            : l.isDueSoon
                                ? "DUE SOON"
                                : l.partyPending <= 0
                                    ? "SETTLED"
                                    : "ACTIVE",
                        style: TextStyle(
                            color: c,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5))),
              ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text("â‚¹${l.freightBilled.toStringAsFixed(0)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: Color(0xFF000000)))),
            Text(
                l.partyPending > 0
                    ? "â‚¹${l.partyPending.toStringAsFixed(0)} due"
                    : "Paid",
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: c)),
          ]),
        ]));
  }

  void _showExpenses() {
    double dsl = ledgers.fold<double>(0, (s, l) => s + l.diesel);
    double tol = ledgers.fold<double>(0, (s, l) => s + l.toll);
    double drv = ledgers.fold<double>(0, (s, l) => s + l.driverExp);
    double los = ledgers.fold<double>(0, (s, l) => s + l.materialLoss);
    double mkt = ledgers
        .where((l) => l.ownership == VehicleOwnership.market)
        .fold<double>(0, (s, l) => s + l.marketTruckFreight);
    double pen = ledgers.fold<double>(0, (s, l) => s + l.penalties);
    double tds = ledgers.fold<double>(0, (s, l) => s + l.tdsDeduction);
    double rev = ledgers.fold<double>(0, (s, l) => s + l.freightBilled);
    double out = dsl + tol + drv + los + mkt + pen + tds;
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (c) => Container(
              decoration: const BoxDecoration(
                  color: Color(0xFFFBF7F0),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28))),
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 20),
                const Text("Financial Breakdown",
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const Divider(height: 28, thickness: 1.5),
                _eRow("ðŸ’§ Diesel Fuel", dsl, Colors.orange),
                _eRow("ðŸš§ Toll / FASTag", tol, Colors.blue),
                _eRow("ðŸ‘¤ Driver Expenses", drv, Colors.purple),
                _eRow("ðŸ“¦ Material Loss", los, Colors.red[900]!),
                _eRow("ðŸš› Market Trucks", mkt, Colors.red),
                _eRow("âš¡ Penalties", pen, Colors.deepOrange),
                _eRow("ðŸ› TDS Deducted", tds, Colors.brown),
                const Divider(height: 28, thickness: 1.5),
                _eRow("ðŸ“Š Total Outflow", out, Colors.black87, b: true),
                _eRow("ðŸ’° Net Margin", rev - out, Colors.green, b: true),
              ]),
            ));
  }

  Widget _eRow(String l, double v, Color c, {bool b = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l,
            style: TextStyle(
                fontSize: 14,
                fontWeight: b ? FontWeight.w900 : FontWeight.w600)),
        Text("â‚¹${v.toStringAsFixed(0)}",
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c))
      ]));

  void _trackDialog() {
    final ctrl = TextEditingController();
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text("Track Vehicle",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                      controller: ctrl,
                      decoration: InputDecoration(
                          labelText: "Vehicle Number",
                          prefixIcon: const Icon(Icons.local_shipping),
                          filled: true,
                          fillColor: const Color(0xFFFFF8E1),
                          labelStyle: const TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                          floatingLabelStyle: const TextStyle(
                              color: Color(0xFFFB8C00),
                              fontWeight: FontWeight.w800,
                              fontSize: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFFB8C00))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFFB8C00))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFFFB8C00), width: 2)))),
                  if (fleet.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                        spacing: 8,
                        children: fleet.take(8).map<Widget>((a) {
                          final asset = a;
                          return GestureDetector(
                              onTap: () => ctrl.text = asset.number,
                              child: Chip(
                                  label: Text(asset.number,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                  backgroundColor:
                                      Colors.blue.withOpacity(0.18)));
                        }).toList())
                  ]
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel")),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF8E1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => LiveTrackingScreen(
                                    route: "Live Tracking",
                                    vehicleNo:
                                        ctrl.text.isEmpty && fleet.isNotEmpty
                                            ? fleet.first.number
                                            : ctrl.text.toUpperCase())));
                      },
                      child: const Text("Track Now",
                          style: TextStyle(color: Color(0xFF000000))))
                ]));
  }

  // â”€â”€ FIND LOAD â”€â”€
  Widget _buildFindLoad() {
    final allStates = [
      'All',
      ...kIndianCities.map((c) => c['state']!).toSet().toList()..sort()
    ];
    final vis = marketLoads
        .where((l) =>
            (l.status == BidStatus.pending || l.status == BidStatus.booked) &&
            (_fOriginState == 'All' || l.originState == _fOriginState) &&
            (_fDestState == 'All' || l.destState == _fDestState))
        .toList();
    return Column(children: [
      Container(
          color: const Color(0xFFFFF8E1),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Load Board",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF000000))),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green[200]!)),
                  child: Text("${vis.length} Active",
                      style: TextStyle(
                          color: Colors.green[800],
                          fontSize: 11,
                          fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: DropdownButtonFormField<String>(
                      style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                      isExpanded: true,
                      initialValue: _fOriginState,
                      decoration: InputDecoration(
                          labelText: "From State",
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.trip_origin,
                              size: 16, color: Colors.green)),
                      items: allStates
                          .map((s) => DropdownMenuItem<String>(
                              value: s,
                              child: Text(s,
                                  style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (v) => setState(() => _fOriginState = v!))),
              const SizedBox(width: 10),
              Expanded(
                  child: DropdownButtonFormField<String>(
                      style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                      isExpanded: true,
                      initialValue: _fDestState,
                      decoration: InputDecoration(
                          labelText: "To State",
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.location_on,
                              size: 16, color: Colors.red)),
                      items: allStates
                          .map((s) => DropdownMenuItem<String>(
                              value: s,
                              child: Text(s,
                                  style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (v) => setState(() => _fDestState = v!))),
            ]),
          ])),
      vis.isEmpty
          ? const Expanded(
              child: Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                  Icon(Icons.search_off, size: 60, color: Colors.grey),
                  SizedBox(height: 12),
                  Text("No loads found",
                      style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text("Try different state filters",
                      style: TextStyle(color: Colors.grey))
                ])))
          : Expanded(
              child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: vis.length,
                  itemBuilder: (ctx, i) {
                    final load = vis[i];
                    return Container(
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                            color: const Color(0xFF000000),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFFB8C00))),
                        child: Column(children: [
                          // Header with gradient
                          Container(
                              padding: const EdgeInsets.all(18),
                              decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFFFF8E1),
                                        Color(0xFFFFF8E1),
                                        Color(0xFF1D4ED8)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20))),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Wrap(
                                                    spacing: 4,
                                                    runSpacing: 4,
                                                    children: [
                                                      Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 3),
                                                          decoration: BoxDecoration(
                                                              color: Colors.green
                                                                  .withOpacity(
                                                                      0.2),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                      8),
                                                              border: Border.all(
                                                                  color: Colors
                                                                      .green
                                                                      .withOpacity(
                                                                          0.4))),
                                                          child: Text(load.originState.isNotEmpty ? load.originState : "Origin",
                                                              style: const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Color(0xFFFB8C00),
                                                                  fontWeight: FontWeight.bold))),
                                                      const Padding(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal:
                                                                      4),
                                                          child: Icon(
                                                              Icons
                                                                  .arrow_forward,
                                                              color: Color(
                                                                  0x541C1917),
                                                              size: 12)),
                                                      Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3),
                                                          decoration: BoxDecoration(
                                                              color: Colors.red
                                                                  .withOpacity(
                                                                      0.2),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                      8),
                                                              border: Border.all(
                                                                  color: Colors
                                                                      .red
                                                                      .withOpacity(
                                                                          0.4))),
                                                          child: Text(load.destState.isNotEmpty ? load.destState : "Dest",
                                                              style: const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Color(0xFFE53E3E),
                                                                  fontWeight: FontWeight.bold))),
                                                    ]),
                                                const SizedBox(height: 8),
                                                Text(load.route,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 14,
                                                        color: Color(
                                                            0xFF1A3A2A)),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 2),
                                              ])),
                                          const SizedBox(width: 12),
                                          Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                    "â‚¹${(load.targetPrice / 1000).toStringAsFixed(0)}K",
                                                    style: const TextStyle(
                                                        color: Color(
                                                            0xFF52A06A),
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 26)),
                                                const Text("target freight",
                                                    style: TextStyle(
                                                        color:
                                                            Color(0x381C1917),
                                                        fontSize: 9)),
                                              ]),
                                        ]),
                                  ])),
                          // Body with details
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Chips row
                                    Wrap(spacing: 8, runSpacing: 6, children: [
                                      _chip(Icons.local_shipping,
                                          load.vehicleType, Colors.blue),
                                      if (load.materialType.isNotEmpty)
                                        _chip(Icons.science, load.materialType,
                                            Colors.purple),
                                      if (load.weightTons > 0)
                                        _chip(Icons.scale,
                                            "${load.weightTons}T", Colors.teal),
                                      if (load.postedDate.isNotEmpty)
                                        _chip(Icons.calendar_today,
                                            load.postedDate, Colors.grey),
                                    ]),
                                    if (load.originFactory.isNotEmpty ||
                                        load.destFactory.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      if (load.originFactory.isNotEmpty)
                                        Row(children: [
                                          Container(
                                              width: 3,
                                              height: 14,
                                              color: Colors.green,
                                              margin: const EdgeInsets.only(
                                                  right: 8)),
                                          Expanded(
                                              child: Text(
                                                  "Loading: ${load.originFactory}",
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.indigo,
                                                      fontWeight:
                                                          FontWeight.w700),
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                        ]),
                                      if (load.destFactory.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(children: [
                                          Container(
                                              width: 3,
                                              height: 14,
                                              color: Colors.red,
                                              margin: const EdgeInsets.only(
                                                  right: 8)),
                                          Expanded(
                                              child: Text(
                                                  "Unloading: ${load.destFactory}",
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.deepOrange,
                                                      fontWeight:
                                                          FontWeight.w700),
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                        ])
                                      ],
                                    ],
                                    const SizedBox(height: 14),
                                    if (load.status == BidStatus.booked)
                                      Column(children: [
                                        Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                                color: Colors.green
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                    color:
                                                        Colors.green.shade700)),
                                            child: const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.check_circle,
                                                      color: Colors.green,
                                                      size: 16),
                                                  SizedBox(width: 6),
                                                  Text("BOOKED âœ“",
                                                      style: TextStyle(
                                                          color: Colors.green,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          fontSize: 13))
                                                ])),
                                        const SizedBox(height: 8),
                                        // Always show Fill Details button â€” user can reopen form anytime
                                        SizedBox(
                                            width: double.infinity,
                                            height: 44,
                                            child: OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                    side: const BorderSide(
                                                        color: Color(
                                                            0xFF3D7A52)),
                                                    shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                12))),
                                                onPressed: () => _showNewEntry(
                                                    prefillRoute: load.route,
                                                    prefillFreight:
                                                        load.targetPrice,
                                                    prefillMaterial:
                                                        load.materialType,
                                                    prefillOriginCity:
                                                        load.originCity,
                                                    prefillOriginState:
                                                        load.originState,
                                                    prefillDestCity:
                                                        load.destCity,
                                                    prefillDestState:
                                                        load.destState,
                                                    prefillFactory: load.originFactory,
                                                    prefillDestFactory: load.destFactory,
                                                    prefillWeight: load.weightTons,
                                                    prefillVehicleType: load.vehicleType),
                                                icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFFFB8C00)),
                                                label: const Text("Fill / Edit Dispatch Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFB8C00))))),
                                        const SizedBox(height: 8),
                                        // Consignor verification status
                                        Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                                color: Colors.amber
                                                    .withOpacity(0.08),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                    color: Colors.amber
                                                        .withOpacity(0.3))),
                                            child: const Row(children: [
                                              Icon(
                                                  Icons.pending_actions_rounded,
                                                  color: Colors.amber,
                                                  size: 14),
                                              SizedBox(width: 6),
                                              Flexible(
                                                  child: Text(
                                                      "Waiting for consignor to verify fleet & documents",
                                                      style: TextStyle(
                                                          color: Colors.amber,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600)))
                                            ])),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                            width: double.infinity,
                                            height: 44,
                                            child: ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors
                                                        .green,
                                                    foregroundColor:
                                                        const Color(0xFFFFF8E1),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12))),
                                                onPressed: () {
                                                  setState(() {
                                                    load.status =
                                                        BidStatus.inTransit;
                                                  });
                                                  _save();
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(const SnackBar(
                                                          backgroundColor:
                                                              Colors.green,
                                                          behavior:
                                                              SnackBarBehavior
                                                                  .floating,
                                                          content: Text(
                                                              "âœ… Load dispatched! Consignor will see update.")));
                                                },
                                                icon: const Icon(
                                                    Icons.local_shipping,
                                                    size: 16),
                                                label: const Text(
                                                    "Mark as Dispatched",
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14)))),
                                      ])
                                    else
                                      SizedBox(
                                          width: double.infinity,
                                          height: 46,
                                          child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFFFFF8E1),
                                                  foregroundColor:
                                                      const Color(0xFFFFF8E1),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12)),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          vertical: 12)),
                                              onPressed: () => _bookLoad(load),
                                              icon: const Icon(
                                                  Icons.check_circle,
                                                  size: 16),
                                              label: const Text(
                                                  "Book & Dispatch",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14)))),
                                  ])),
                        ]));
                  })),
    ]);
  }

  void _bookLoad(MarketLoad load) {
    // Check if fleet has a matching vehicle type
    final hasVehicle = fleet.any((v) => v.type.toLowerCase().contains(
        load.vehicleType.toLowerCase().split(' ').first.toLowerCase()));
    if (!hasVehicle && fleet.isNotEmpty) {
      showDialog(
          context: context,
          builder: (c) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                title: const Row(children: [
                  Icon(Icons.warning_amber, color: Colors.orange),
                  SizedBox(width: 8),
                  Text("Vehicle Not Available",
                      style: TextStyle(fontWeight: FontWeight.bold))
                ]),
                content: Text(
                    "This load requires a ${load.vehicleType}.\n\nYou don't have this vehicle type in your fleet. You can still proceed if you plan to hire a market truck."),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Go Back")),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange),
                      onPressed: () {
                        Navigator.pop(c);
                        _confirmBooking(load);
                      },
                      child: const Text("Proceed Anyway",
                          style: TextStyle(color: Color(0xFF000000)))),
                ],
              ));
      return;
    }
    _confirmBooking(load);
  }

  void _confirmBooking(MarketLoad load) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: const Text("Confirm Booking",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Route: ${load.route}",
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text("Freight: â‚¹${load.targetPrice.toStringAsFixed(0)}",
                        style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    const SizedBox(height: 10),
                    // Platform commission disclosure
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(children: [
                                Icon(Icons.info_outline,
                                    size: 14, color: Colors.amber),
                                SizedBox(width: 6),
                                Text("Platform Commission",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: Colors.amber))
                              ]),
                              const SizedBox(height: 6),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Your commission (2%)",
                                        style: TextStyle(fontSize: 11)),
                                    Text(
                                        "â‚¹${(load.targetPrice * 0.02).toStringAsFixed(0)}",
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.red))
                                  ]),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Consignor commission (2%)",
                                        style: TextStyle(fontSize: 11)),
                                    Text(
                                        "â‚¹${(load.targetPrice * 0.02).toStringAsFixed(0)}",
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.red))
                                  ]),
                              const Divider(height: 10),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("You receive (net)",
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11)),
                                    Text(
                                        "â‚¹${(load.targetPrice * 0.98).toStringAsFixed(0)}",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            color: Colors.green))
                                  ]),
                            ])),
                    const SizedBox(height: 8),
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text(
                            "Load stays on board until consignor verifies. Tap 'Mark Dispatched' after physical dispatch.",
                            style: TextStyle(
                                fontSize: 11, color: Colors.blueGrey))),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text("Cancel")),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF8E1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      Navigator.pop(c);
                      setState(() {
                        load.status = BidStatus.booked;
                      }); // stays on board as 'booked'
                      _save();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                              "âœ… Load booked! Fill dispatch details and mark dispatched when ready.")));
                      Future.delayed(
                          const Duration(milliseconds: 300),
                          () => _showNewEntry(
                              prefillRoute: load.route,
                              prefillFreight: load.targetPrice,
                              prefillMaterial: load.materialType,
                              prefillOriginCity: load.originCity,
                              prefillOriginState: load.originState,
                              prefillDestCity: load.destCity,
                              prefillDestState: load.destState,
                              prefillFactory: load.originFactory,
                              prefillDestFactory: load.destFactory,
                              prefillWeight: load.weightTons,
                              prefillVehicleType: load.vehicleType));
                    },
                    child: const Text("Book & Fill Details",
                        style: TextStyle(color: Color(0xFF000000)))),
              ],
            ));
  }

  // â”€â”€ POST LOAD â”€â”€
  Widget _buildPostLoad() {
    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Post a Requirement",
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF000000))),
          const SizedBox(height: 6),
          const Text("Broadcast to verified fleet operators",
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          Container(
              decoration: BoxDecoration(
                  color: const Color(0xFF000000),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05), blurRadius: 20)
                  ]),
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Loading Point",
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Color(0xFF000000))),
                    const SizedBox(height: 8),
                    CitySearchField(
                        controller: _pOriginCtrl,
                        label: "Origin City",
                        icon: Icons.trip_origin,
                        iconColor: Colors.green,
                        onCitySelected: (city, state, pid) => setState(() {
                              _pOriginCity = city;
                              _pOriginState = state;
                            })),
                    if (_pOriginState.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Row(children: [
                            Icon(Icons.location_on,
                                size: 12, color: Colors.green[700]),
                            const SizedBox(width: 4),
                            Text(_pOriginState,
                                style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700))
                          ])),
                    const SizedBox(height: 10),
                    FactorySearchField(
                      controller: _pFactoryOriginCtrl,
                      label: "Loading Factory / Plant Name",
                      iconColor: Colors.green,
                      onSelected: (name, pid) => setState(() {
                        if (name.isNotEmpty) _pFactoryOriginCtrl.text = name;
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Text("Unloading Point",
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Color(0xFF000000))),
                    const SizedBox(height: 8),
                    CitySearchField(
                        controller: _pDestCtrl,
                        label: "Destination City",
                        icon: Icons.location_on,
                        iconColor: Colors.red,
                        onCitySelected: (city, state, pid) => setState(() {
                              _pDestCity = city;
                              _pDestState = state;
                            })),
                    if (_pDestState.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Row(children: [
                            Icon(Icons.location_on,
                                size: 12, color: Colors.red[700]),
                            const SizedBox(width: 4),
                            Text(_pDestState,
                                style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700))
                          ])),
                    const SizedBox(height: 10),
                    FactorySearchField(
                      controller: _pFactoryDestCtrl,
                      label: "Unloading Factory / Depot Name",
                      iconColor: Colors.red,
                      onSelected: (name, pid) => setState(() {
                        if (name.isNotEmpty) _pFactoryDestCtrl.text = name;
                      }),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: _pWeightCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: "Weight (Tons)",
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2))))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: DropdownButtonFormField<String>(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              isExpanded: true,
                              initialValue: _pVehicleType,
                              decoration: InputDecoration(
                                  labelText: "Vehicle Type",
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2))),
                              items: ["SS Tanker", "MS Tanker", "Container", "Open Truck", "Trailer", "LCV", "Reefer"]
                                  .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Color(0xFF000000)))))
                                  .toList(),
                              onChanged: (v) => setState(() => _pVehicleType = v!))),
                    ]),
                    const SizedBox(height: 16),
                    TextField(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        controller: _pMaterialCtrl,
                        decoration: InputDecoration(
                            labelText:
                                "Material (e.g. Ethanol, Acid, Chemicals)",
                            prefixIcon: const Icon(Icons.science,
                                color: Colors.purple, size: 20),
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00),
                                    width: 2)))),
                    const SizedBox(height: 16),
                    TextField(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        controller: _pPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: "Target Freight (â‚¹)",
                            prefixIcon: const Icon(Icons.currency_rupee,
                                color: Colors.green, size: 20),
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00),
                                    width: 2)))),
                    const SizedBox(height: 28),
                    SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[800],
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          onPressed: () {
                            if (_pOriginCtrl.text.isEmpty ||
                                _pDestCtrl.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text("Enter origin and destination"),
                                      backgroundColor: Colors.red));
                              return;
                            }
                            setState(() {
                              marketLoads.insert(
                                  0,
                                  MarketLoad(
                                      id: "L${math.Random().nextInt(9999)}",
                                      route:
                                          "${_pOriginCtrl.text} â†’ ${_pDestCtrl.text}",
                                      details:
                                          "${_pWeightCtrl.text.isNotEmpty ? '${_pWeightCtrl.text}T | ' : ''}${_pMaterialCtrl.text}",
                                      vehicleType: _pVehicleType,
                                      targetPrice:
                                          double.tryParse(_pPriceCtrl.text) ??
                                              0,
                                      materialType: _pMaterialCtrl.text,
                                      originCity: _pOriginCity,
                                      originState: _pOriginState,
                                      destCity: _pDestCity,
                                      destState: _pDestState,
                                      originFactory: _pFactoryOriginCtrl.text,
                                      destFactory: _pFactoryDestCtrl.text,
                                      weightTons:
                                          double.tryParse(_pWeightCtrl.text) ??
                                              0,
                                      postedDate:
                                          "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}"));
                              // Push to Firestore so ALL users see this load
                              if (FirebaseService.isReady) {
                                final newLoad = marketLoads.first;
                                FirebaseFirestore.instance
                                    .collection('marketLoads')
                                    .doc(newLoad.id)
                                    .set({
                                  ...newLoad.toJson(),
                                  'status': newLoad.status.index,
                                  'postedBy':
                                      FirebaseService.currentUser?.uid ??
                                          'local',
                                }).catchError((_) {});
                              }
                              _idx = 1;
                            });
                            _pOriginCtrl.clear();
                            _pDestCtrl.clear();
                            _pFactoryOriginCtrl.clear();
                            _pFactoryDestCtrl.clear();
                            _pWeightCtrl.clear();
                            _pPriceCtrl.clear();
                            setState(() {
                              _pOriginState = '';
                              _pDestState = '';
                              _pOriginCity = '';
                              _pDestCity = '';
                            });
                            _save();
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                        "âœ… Load Posted to Market Board!")));
                          },
                          icon: const Icon(Icons.broadcast_on_personal,
                              color: Color(0xFF000000)),
                          label: const Text("Broadcast to Market",
                              style: TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                        )),
                  ])),
        ]));
  }

  // â”€â”€ KHATA LEDGER (Refined) â”€â”€
  Widget _buildKhata() {
    List<TripLedger> fl = ledgers;
    if (_khataFilter == "Party" && _khataFilterVal != null) {
      fl = ledgers.where((l) => l.partyName == _khataFilterVal).toList();
    } else if (_khataFilter == "Vehicle" && _khataFilterVal != null)
      fl = ledgers.where((l) => l.vehicleNo == _khataFilterVal).toList();
    else if (_khataFilter == "Due Soon")
      fl = ledgers.where((l) => l.isDueSoon && !l.isPaymentOverdue).toList();
    else if (_khataFilter == "Pending")
      fl = ledgers.where((l) => l.partyPending > 0).toList();
    else if (_khataFilter == "Settled")
      fl = ledgers.where((l) => l.partyPending <= 0).toList();

    double totalPending = fl.fold<double>(
        0, (s, l) => s + (l.partyPending > 0 ? l.partyPending : 0));
    double totalBilled = fl.fold<double>(0, (s, l) => s + l.freightBilled);

    return Scaffold(
      body: Column(children: [
        Container(
            color: const Color(0xFFFFF8E1),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 15),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Khata Ledger",
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: Color(0xFF000000))),
                Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text("${fl.length} entries",
                        style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                            fontSize: 11)),
                    if (totalPending > 0)
                      Text(
                          "â‚¹${(totalPending / 1000).toStringAsFixed(0)}K pending",
                          style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w800,
                              fontSize: 11))
                  ]),
                  const SizedBox(width: 10),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: Color(0xFF000000)),
                    onSelected: (v) {
                      if (v == 'excel') {
                        _exportKhataExcel(fl);
                      } else if (v == 'csv_import') _showCSVImport();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'excel',
                          child: Row(children: [
                            Icon(Icons.table_chart,
                                color: Colors.green, size: 18),
                            SizedBox(width: 10),
                            Text("Export to Excel / CSV")
                          ])),
                      const PopupMenuItem(
                          value: 'csv_import',
                          child: Row(children: [
                            Icon(Icons.upload_file,
                                color: Colors.blue, size: 18),
                            SizedBox(width: 10),
                            Text("Import from CSV")
                          ])),
                    ],
                  ),
                ]),
              ]),
              if (totalBilled > 0)
                Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(children: [
                            const Text("Billed",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                            FittedBox(
                                child: Text(
                                    "â‚¹${(totalBilled / 1000).toStringAsFixed(0)}K",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: Color(0xFF000000))))
                          ]),
                          Column(children: [
                            const Text("Pending",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                            FittedBox(
                                child: Text(
                                    "â‚¹${(totalPending / 1000).toStringAsFixed(0)}K",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: Colors.orange)))
                          ]),
                          Column(children: [
                            const Text("Collected",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                            FittedBox(
                                child: Text(
                                    "â‚¹${((totalBilled - totalPending) / 1000).toStringAsFixed(0)}K",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: Colors.green)))
                          ]),
                        ])),
              const SizedBox(height: 12),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                      children: [
                    "All",
                    "Party",
                    "Vehicle",
                    "Due Soon",
                    "Pending",
                    "Settled"
                  ]
                          .map((t) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                  label: Text(t,
                                      style: TextStyle(
                                          color: _khataFilter == t
                                              ? const Color(0xFFFFF8E1)
                                              : const Color(0xFF000000),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11)),
                                  selected: _khataFilter == t,
                                  selectedColor: const Color(0xFFFB8C00),
                                  backgroundColor: const Color(0xFFFFF8E1),
                                  side: BorderSide(
                                      color: _khataFilter == t
                                          ? const Color(0xFFFB8C00)
                                          : const Color(0xFFFB8C00)),
                                  onSelected: (_) => setState(() {
                                        _khataFilter = t;
                                        _khataFilterVal = null;
                                      }))))
                          .toList())),
              if (_khataFilter == "Party" && ledgers.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                    initialValue: _khataFilterVal,
                    isDense: true,
                    hint: const Text("Select Party"),
                    decoration: InputDecoration(
                        labelText: "Filter by Party",
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2))),
                    items: ledgers
                        .map((e) => (e).partyName)
                        .toSet()
                        .map((p) => DropdownMenuItem<String>(
                            value: p,
                            child: Text(p, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _khataFilterVal = v))
              ],
              if (_khataFilter == "Vehicle" && ledgers.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                    initialValue: _khataFilterVal,
                    isDense: true,
                    hint: const Text("Select Vehicle"),
                    decoration: InputDecoration(
                        labelText: "Filter by Vehicle",
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2))),
                    items: ledgers
                        .map((e) => (e).vehicleNo)
                        .where((v) => (v).isNotEmpty)
                        .toSet()
                        .map((v) => DropdownMenuItem<String>(
                            value: v,
                            child: Text(v, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _khataFilterVal = v))
              ],
            ])),
        Expanded(
            child: fl.isEmpty
                ? const Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Icon(Icons.menu_book, size: 60, color: Colors.grey),
                        SizedBox(height: 12),
                        Text("No trips found",
                            style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 16))
                      ]))
                : ListView.builder(
                    padding: const EdgeInsets.all(15),
                    itemCount: fl.length,
                    itemBuilder: (ctx, i) {
                      final l = fl[i];
                      final sc = l.isPaymentOverdue
                          ? Colors.red
                          : l.isDueSoon
                              ? Colors.orange
                              : l.partyPending <= 0
                                  ? Colors.green
                                  : Colors.blueGrey;
                      final st = l.partyPending <= 0
                          ? "Settled"
                          : l.isPaymentOverdue
                              ? "OVERDUE â‚¹${l.partyPending.toStringAsFixed(0)}"
                              : l.isDueSoon
                                  ? "DUE SOON â‚¹${l.partyPending.toStringAsFixed(0)}"
                                  : "â‚¹${l.partyPending.toStringAsFixed(0)} Pending";
                      return GestureDetector(
                        onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(
                                builder: (_) => TripDetailScreen(
                                    ledger: l,
                                    userProfile: userProfile,
                                    subscription: subscription,
                                    drivers: drivers,
                                    onUpdateLedger: (upd) {
                                      final idx = ledgers
                                          .indexWhere((x) => x.id == l.id);
                                      if (idx >= 0) {
                                        setState(() => ledgers[idx] = upd);
                                        _save();
                                      }
                                    },
                                    onKredXApply: (a) {
                                      setState(() => kredxApps.insert(0, a));
                                      _save();
                                    }))),
                        child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                                color: const Color(0xFF000000),
                                borderRadius: BorderRadius.circular(16),
                                border: Border(
                                    left: BorderSide(color: sc, width: 4)),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3))
                                ]),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(children: [
                                          Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                  color: sc,
                                                  shape: BoxShape.circle)),
                                          const SizedBox(width: 8),
                                          Text(l.vehicleNo,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14,
                                                  color:
                                                      Color(0xFF000000)))
                                        ]),
                                        Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                                color: sc.withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Text(st,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: sc))),
                                      ]),
                                  const SizedBox(height: 6),
                                  Text(l.partyName,
                                      style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(
                                      "${l.loadingPoint.isNotEmpty ? '${l.loadingPoint} â†’ ${l.unloadingPoint}' : l.route} â€¢ ${l.date}",
                                      style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500)),
                                  if (l.materialName.isNotEmpty)
                                    Text(
                                        "${l.materialName}${l.weightTons > 0 ? ' â€¢ ${l.weightTons} ${l.weightUnit}' : ''}",
                                        style: const TextStyle(
                                            color: Colors.blueGrey,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  const Divider(height: 14),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text("Freight Billed",
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              Text(
                                                  "â‚¹${l.freightBilled.toStringAsFixed(0)}",
                                                  style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w900))
                                            ]),
                                        if (l.tdsDeduction > 0 ||
                                            l.penalties > 0)
                                          Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                const Text("Deductions",
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                Text(
                                                    "â‚¹${(l.tdsDeduction + l.penalties).toStringAsFixed(0)}",
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: Colors.red))
                                              ]),
                                        Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                  l.ownership ==
                                                          VehicleOwnership.self
                                                      ? "Profit"
                                                      : "Commission",
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              Text(
                                                  "â‚¹${l.tripProfit.toStringAsFixed(0)}",
                                                  style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: l.tripProfit >= 0
                                                          ? Colors.green
                                                          : Colors.red))
                                            ]),
                                      ]),
                                ])),
                      );
                    })),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFFFB8C00),
          elevation: 6,
          icon: const Icon(Icons.add, color: Color(0xFF000000)),
          label: const Text("New Entry",
              style: TextStyle(
                  color: Color(0xFF000000),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3)),
          onPressed: () => _showNewEntry()),
    );
  }

  void _exportKhataExcel(List<TripLedger> list) {
    final sb = StringBuffer();
    sb.writeln(
        "Trip ID,Date,Party Name,Vehicle No,Route,Loading Point,Unloading Point,Material,Weight,E-Way Bill,Driver,Freight Billed,Payment Received,TDS,Penalties,Net Pending,Diesel,Toll,Driver Exp,Material Loss,Market Freight,Trip Profit,GST Type,GST Amount,Payment Terms,LR Notes,Status");
    for (final l in list) {
      final status = l.partyPending <= 0
          ? "Settled"
          : l.isPaymentOverdue
              ? "OVERDUE"
              : l.isDueSoon
                  ? "DUE SOON"
                  : "Pending";
      sb.writeln([
        l.id,
        l.date,
        '"${l.partyName}"',
        l.vehicleNo,
        '"${l.route}"',
        '"${l.loadingPoint}"',
        '"${l.unloadingPoint}"',
        '"${l.materialName}"',
        "${l.weightTons} ${l.weightUnit}",
        l.eWayBillNo,
        l.driverName ?? '',
        l.freightBilled.toStringAsFixed(2),
        l.paymentReceived.toStringAsFixed(2),
        l.tdsDeduction.toStringAsFixed(2),
        l.penalties.toStringAsFixed(2),
        l.partyPending.toStringAsFixed(2),
        l.diesel.toStringAsFixed(2),
        l.toll.toStringAsFixed(2),
        l.driverExp.toStringAsFixed(2),
        l.materialLoss.toStringAsFixed(2),
        l.marketTruckFreight.toStringAsFixed(2),
        l.tripProfit.toStringAsFixed(2),
        l.gstType.name,
        l.gstAmount.toStringAsFixed(2),
        l.paymentTermsDays,
        '"${l.lrNotes}"',
        status
      ].join(','));
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        content: Text(
            "âœ… CSV data copied! Paste in Excel or Google Sheets.\nAll columns are properly formatted for Excel.")));
  }

  void _showCSVImport() => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => BankImportScreen(
              ledgers: ledgers,
              onMatch: (id, amt) {
                final i = ledgers.indexWhere((l) => l.id == id);
                if (i >= 0) {
                  setState(() => ledgers[i].paymentReceived += amt);
                  _save();
                }
              })));

  // â”€â”€ NEW ENTRY SHEET â”€â”€
  void _showNewEntry(
      {String? prefillRoute,
      double? prefillFreight,
      String? prefillMaterial,
      String? prefillOriginCity,
      String? prefillOriginState,
      String? prefillDestCity,
      String? prefillDestState,
      String? prefillFactory,
      String? prefillDestFactory,
      double? prefillWeight,
      String? prefillVehicleType}) async {
    if (subscription.isTripsLimitReached) {
      _upgradeBanner("Unlimited Trips (Free: 10/month)");
      return;
    }
    // Check if registration is complete â€” block dispatch until registration is done
    final prefs = await SharedPreferences.getInstance();
    var regDone = prefs.getBool('rm_registration_done') ?? false;
    if (!regDone) {
      if (!mounted) return;
      final wantToRegister = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
                backgroundColor: const Color(0xFFFFF8E1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Row(children: [
                  Icon(Icons.assignment_ind_rounded,
                      color: Color(0xFFFB8C00)),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text("Registration Required",
                          style: TextStyle(
                              color: Color(0xFF000000),
                              fontWeight: FontWeight.w900,
                              fontSize: 16)))
                ]),
                content: const Text(
                    "Before posting or booking loads, please complete your company KYC profile. This is required for invoice generation, GST compliance, and consignor verification.",
                    style: TextStyle(
                        color: Color(0xFF000000), fontSize: 13)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text("Cancel",
                          style: TextStyle(color: Color(0xFF000000)))),
                  GestureDetector(
                      onTap: () => Navigator.pop(c, true),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFFB8C00),
                                Color(0xFF0EA5E9)
                              ]),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Text("Complete Now",
                              style: TextStyle(
                                  color: Color(0xFFFFF8E1),
                                  fontWeight: FontWeight.w800)))),
                ],
              ));
      if (wantToRegister != true) return;
      // Open registration screen and WAIT for it to complete
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => const RegistrationScreen()));
      // Re-check registration status after returning
      final prefs2 = await SharedPreferences.getInstance();
      regDone = prefs2.getBool('rm_registration_done') ?? false;
      if (!regDone) {
        // User backed out of registration â€” block dispatch
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              backgroundColor: Color(0xFFFB8C00),
              behavior: SnackBarBehavior.floating,
              content: Text(
                  "Registration must be completed to post/dispatch loads")));
        }
        return;
      }
    }
    // Start with self fleet always. Only switch to market if fleet has NO matching vehicle.
    final hasMatchingVehicle = prefillVehicleType == null ||
        prefillVehicleType.isEmpty ||
        fleet.any((v) => (v).type.toLowerCase().contains(
            prefillVehicleType.toLowerCase().split(' ').first.toLowerCase()));
    VehicleOwnership own =
        hasMatchingVehicle ? VehicleOwnership.self : VehicleOwnership.market;
    final pCtrl = TextEditingController();
    final vCtrl = TextEditingController();
    final rCtrl = TextEditingController(text: prefillRoute ?? "");
    final fCtrl =
        TextEditingController(text: prefillFreight?.toStringAsFixed(0) ?? "");
    final rcvdCtrl = TextEditingController();
    final dslCtrl = TextEditingController();
    final tolCtrl = TextEditingController();
    final drvCtrl = TextEditingController();
    final losCtrl = TextEditingController();
    final mfCtrl = TextEditingController();
    final maCtrl = TextEditingController();
    final tmCtrl = TextEditingController(text: "30");
    final ewCtrl = TextEditingController();
    final matCtrl =
        TextEditingController(text: prefillMaterial ?? "Chemical/Ethanol");
    final penCtrl = TextEditingController();
    final tdsCtrl = TextEditingController();
    final distCtrl = TextEditingController();
    final feCtrl = TextEditingController(text: "3.5");
    // Auto-calc diesel when km or mileage changes
    void autoCalcDiesel() {
      final km = double.tryParse(distCtrl.text) ?? 0;
      final fe = double.tryParse(feCtrl.text) ?? 3.5;
      if (km > 0 && fe > 0) {
        final calcDsl =
            (km / fe * AppConfig.defaultDieselPrice).round().toString();
        if (dslCtrl.text != calcDsl) dslCtrl.text = calcDsl;
      }
    }

    distCtrl.addListener(autoCalcDiesel);
    feCtrl.addListener(autoCalcDiesel);
    final wtCtrl = TextEditingController(
        text: prefillWeight != null && prefillWeight > 0
            ? prefillWeight.toStringAsFixed(1)
            : '');
    final cpCtrl = TextEditingController();
    final ceCtrl = TextEditingController();
    final cgCtrl = TextEditingController();
    final notCtrl = TextEditingController();
    String? selVeh = fleet.isNotEmpty ? fleet.first.number : null;
    String? selDrv;
    String wUnit = "MT",
        lOCity = prefillOriginCity ?? '',
        lDCity = prefillDestCity ?? '';
    final wtCtrl2 = TextEditingController(
        text: prefillWeight != null && prefillWeight > 0
            ? prefillWeight.toStringAsFixed(1)
            : '');
    String lOState = prefillOriginState ?? '', lDState = prefillDestState ?? '';
    GstType gst = GstType.none;
    double gstRate = 5.0;
    bool gstInc = false;
    bool calcDone = false;
    final invCtrl = TextEditingController(); // material invoice number
    final List<InvoiceItem> partItems = []; // part load items
    // Factory / plant fields â€” placeId gives precise coordinates for Google Maps routing
    final loFactCtrl = TextEditingController(text: prefillFactory ?? '');
    final ldFactCtrl = TextEditingController(text: prefillDestFactory ?? '');
    String loFactName = prefillFactory ?? '', loFactPlaceId = '';
    String ldFactName = prefillDestFactory ?? '', ldFactPlaceId = '';
    String lOCityPlaceId = '', lDCityPlaceId = '';

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setS) => Container(
                  height: MediaQuery.of(ctx).size.height * 0.97,
                  decoration: const BoxDecoration(
                      color: Color(0xFFFBF7F0),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28))),
                  padding: EdgeInsets.only(
                      top: 24,
                      left: 20,
                      right: 20,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom),
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("New Dispatch Entry",
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF000000))),
                              IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Color(0xFF000000)),
                                  onPressed: () => Navigator.pop(ctx)),
                            ]),
                        const SizedBox(height: 16),
                        SegmentedButton<VehicleOwnership>(
                            style: SegmentedButton.styleFrom(
                                selectedBackgroundColor:
                                    const Color(0xFFFB8C00),
                                selectedForegroundColor:
                                    const Color(0xFFFFF8E1),
                                backgroundColor: const Color(0xFFFFF8E1)),
                            segments: const [
                              ButtonSegment(
                                  value: VehicleOwnership.self,
                                  icon: Icon(Icons.local_shipping, size: 14),
                                  label: Text("Self Fleet")),
                              ButtonSegment(
                                  value: VehicleOwnership.market,
                                  icon: Icon(Icons.handshake, size: 14),
                                  label: Text("Market Truck"))
                            ],
                            selected: {own},
                            onSelectionChanged: (v) =>
                                setS(() => own = v.first)),
                        const SizedBox(height: 16),

                        // Party + Terms
                        Row(children: [
                          Expanded(
                              flex: 2,
                              child: TextField(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  controller: pCtrl,
                                  decoration: InputDecoration(
                                      labelText: "Party / Consignor Name *",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00),
                                              width: 2))))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: TextField(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  controller: tmCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                      labelText: "Terms (Days)",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00),
                                              width: 2))))),
                        ]),
                        const SizedBox(height: 12),
                        // Consignor details
                        ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text("Consignor Contact & GST",
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF000000))),
                            children: [
                              Row(children: [
                                Expanded(
                                    child: TextField(
                                        style: const TextStyle(
                                            color: Color(0xFF000000),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                        controller: cpCtrl,
                                        keyboardType: TextInputType.phone,
                                        decoration: InputDecoration(
                                            labelText: "Consignor Phone",
                                            filled: true,
                                            fillColor: const Color(0xFFFFF8E1),
                                            border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFFFB8C00))),
                                            enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFFFB8C00))),
                                            focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                    color:
                                                        Color(0xFFFB8C00),
                                                    width: 2))))),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: TextField(
                                        style: const TextStyle(
                                            color: Color(0xFF000000),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                        controller: cgCtrl,
                                        decoration: InputDecoration(
                                            labelText: "GSTIN",
                                            filled: true,
                                            fillColor: const Color(0xFFFFF8E1),
                                            border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFFFB8C00))),
                                            enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFFFB8C00))),
                                            focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                    color:
                                                        Color(0xFFFB8C00),
                                                    width: 2)))))
                              ]),
                              const SizedBox(height: 8),
                              TextField(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  controller: ceCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                      labelText:
                                          "Consignor Email (for auto-docs)",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00),
                                              width: 2)))),
                              const SizedBox(height: 8),
                            ]),
                        const SizedBox(height: 10),

                        // Route
                        const Text("Route Details",
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Color(0xFF000000))),
                        const SizedBox(height: 4),
                        // Origin
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: const Color(0xFF000000),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.green.withOpacity(0.4))),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.green)),
                                    const SizedBox(width: 8),
                                    const Text("LOADING / ORIGIN",
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF15803D),
                                            letterSpacing: 1))
                                  ]),
                                  const SizedBox(height: 8),
                                  FactorySearchField(
                                    controller: loFactCtrl,
                                    label: "Factory / Plant Name (Loading)",
                                    iconColor: Colors.green,
                                    onSelected: (name, pid) {
                                      setS(() {
                                        loFactName = name;
                                        loFactPlaceId = pid;
                                        if (rCtrl.text.isEmpty) {
                                          rCtrl.text =
                                              "$name â†’ ${ldFactName.isNotEmpty ? ldFactName : lDCity}";
                                        }
                                      });
                                      // Auto-calc against ANY destination (factory OR city)
                                      final destName = ldFactName.isNotEmpty
                                          ? ldFactName
                                          : lDCity;
                                      final destPid = ldFactPlaceId.isNotEmpty
                                          ? ldFactPlaceId
                                          : lDCityPlaceId;
                                      if (destName.isNotEmpty &&
                                          name.isNotEmpty) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  backgroundColor:
                                                      const Color(0xFFFB8C00),
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  duration: const Duration(
                                                      seconds: 2),
                                                  content: Row(children: const [
                                                    SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                            color: Color(
                                                                0xFFF2EDE4),
                                                            strokeWidth: 2)),
                                                    SizedBox(width: 10),
                                                    Text(
                                                        "ðŸ“ Calculating distance via Google Maps...")
                                                  ])));
                                        }
                                        Future.delayed(
                                            const Duration(milliseconds: 400),
                                            () async {
                                          int ax = 6;
                                          try {
                                            if (selVeh != null) {
                                              ax = fleet
                                                  .firstWhere(
                                                      (v) => v.number == selVeh)
                                                  .axleCount;
                                            }
                                          } catch (_) {}
                                          final res =
                                              await RoutingEngine.calculate(
                                                  origin: name,
                                                  destination: destName,
                                                  axles: ax,
                                                  fuelEconomy: double.tryParse(
                                                          feCtrl.text) ??
                                                      3.5,
                                                  originPlaceId: pid,
                                                  destPlaceId: destPid);
                                          final km = res['km'] as int? ?? 0;
                                          if (km > 0 && mounted) {
                                            setS(() {
                                              distCtrl.text = km.toString();
                                              tolCtrl.text =
                                                  res['toll'].toString();
                                              dslCtrl.text =
                                                  res['diesel'].toString();
                                              calcDone = true;
                                            });
                                            final src =
                                                res['source'] as String? ?? '';
                                            final srcLabel =
                                                src.startsWith('google')
                                                    ? 'Google Maps'
                                                    : src == 'smart_engine'
                                                        ? 'Smart Engine'
                                                        : 'Estimated';
                                            ScaffoldMessenger.of(context)
                                                .hideCurrentSnackBar();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    backgroundColor:
                                                        Colors.green.shade700,
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                    duration: const Duration(
                                                        seconds: 4),
                                                    content: Text(
                                                        "âœ… $km km Â· â‚¹${res['diesel']} diesel Â· â‚¹${res['toll']} FASTag ($srcLabel)")));
                                          } else if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .hideCurrentSnackBar();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    backgroundColor:
                                                        Colors.orange.shade700,
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                    duration: const Duration(
                                                        seconds: 4),
                                                    content: Text(
                                                        "âš ï¸ Could not calculate. Please enter distance manually. (${res['source']})")));
                                          }
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  CitySearchField(
                                      label: "Loading City",
                                      icon: Icons.location_city,
                                      iconColor: Colors.green,
                                      initialValue: prefillOriginCity ?? '',
                                      onCitySelected: (city, state, pid) {
                                        setS(() {
                                          lOCity = city;
                                          lOState = state;
                                          lOCityPlaceId = pid;
                                        });
                                        // Auto-calc if destination is already known
                                        final dest = ldFactName.isNotEmpty
                                            ? ldFactName
                                            : lDCity;
                                        final dPid = ldFactPlaceId.isNotEmpty
                                            ? ldFactPlaceId
                                            : lDCityPlaceId;
                                        if (dest.isNotEmpty) {
                                          Future.delayed(
                                              const Duration(milliseconds: 300),
                                              () async {
                                            int ax = 6;
                                            try {
                                              if (selVeh != null) {
                                                ax = fleet
                                                    .firstWhere((v) =>
                                                        v.number == selVeh)
                                                    .axleCount;
                                              }
                                            } catch (_) {}
                                            final res =
                                                await RoutingEngine.calculate(
                                                    origin: city,
                                                    destination: dest,
                                                    axles: ax,
                                                    fuelEconomy:
                                                        double.tryParse(
                                                                feCtrl.text) ??
                                                            3.5,
                                                    originPlaceId: pid,
                                                    destPlaceId: dPid);
                                            if ((res['km'] as int? ?? 0) > 0) {
                                              setS(() {
                                                distCtrl.text =
                                                    res['km'].toString();
                                                tolCtrl.text =
                                                    res['toll'].toString();
                                                dslCtrl.text =
                                                    res['diesel'].toString();
                                                calcDone = true;
                                              });
                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        backgroundColor: Colors
                                                            .green.shade700,
                                                        behavior:
                                                            SnackBarBehavior
                                                                .floating,
                                                        duration:
                                                            const Duration(
                                                                seconds: 3),
                                                        content: Text(
                                                            "ðŸ“ ${res['km']} km Â· â‚¹${res['diesel']} diesel Â· â‚¹${res['toll']} toll")));
                                              }
                                            }
                                          });
                                        }
                                      }),
                                  if (lOState.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(
                                            top: 4, left: 4),
                                        child: Text(lOState,
                                            style: TextStyle(
                                                color: Colors.green[700],
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700))),
                                ])),
                        const SizedBox(height: 6),
                        Center(
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF000000),
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.arrow_downward,
                                          size: 12,
                                          color: Color(0xFF000000)),
                                      SizedBox(width: 4),
                                      Text("TO",
                                          style: TextStyle(
                                              color: Color(0xFF000000),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1))
                                    ]))),
                        const SizedBox(height: 6),
                        // Destination
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: const Color(0xFF000000),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.red.withOpacity(0.4))),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.red)),
                                    const SizedBox(width: 8),
                                    const Text("UNLOADING / DESTINATION",
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFFF6B6B),
                                            letterSpacing: 1))
                                  ]),
                                  const SizedBox(height: 8),
                                  FactorySearchField(
                                    controller: ldFactCtrl,
                                    label: "Factory / Depot Name (Unloading)",
                                    iconColor: Colors.red,
                                    onSelected: (name, pid) {
                                      setS(() {
                                        ldFactName = name;
                                        ldFactPlaceId = pid;
                                        rCtrl.text =
                                            "${loFactName.isNotEmpty ? loFactName : lOCity} â†’ $name";
                                      });
                                      // Auto-calc against ANY origin (factory OR city)
                                      final origName = loFactName.isNotEmpty
                                          ? loFactName
                                          : lOCity;
                                      final origPid = loFactPlaceId.isNotEmpty
                                          ? loFactPlaceId
                                          : lOCityPlaceId;
                                      if (origName.isNotEmpty &&
                                          name.isNotEmpty) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  backgroundColor:
                                                      const Color(0xFFFB8C00),
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  duration: const Duration(
                                                      seconds: 2),
                                                  content: Row(children: const [
                                                    SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                            color: Color(
                                                                0xFFF2EDE4),
                                                            strokeWidth: 2)),
                                                    SizedBox(width: 10),
                                                    Text(
                                                        "ðŸ“ Calculating distance via Google Maps...")
                                                  ])));
                                        }
                                        Future.delayed(
                                            const Duration(milliseconds: 400),
                                            () async {
                                          int ax = 6;
                                          try {
                                            if (selVeh != null) {
                                              ax = fleet
                                                  .firstWhere(
                                                      (v) => v.number == selVeh)
                                                  .axleCount;
                                            }
                                          } catch (_) {}
                                          final res =
                                              await RoutingEngine.calculate(
                                                  origin: origName,
                                                  destination: name,
                                                  axles: ax,
                                                  fuelEconomy: double.tryParse(
                                                          feCtrl.text) ??
                                                      3.5,
                                                  originPlaceId: origPid,
                                                  destPlaceId: pid);
                                          final km = res['km'] as int? ?? 0;
                                          if (km > 0 && mounted) {
                                            setS(() {
                                              distCtrl.text = km.toString();
                                              tolCtrl.text =
                                                  res['toll'].toString();
                                              dslCtrl.text =
                                                  res['diesel'].toString();
                                              calcDone = true;
                                            });
                                            final src =
                                                res['source'] as String? ?? '';
                                            final srcLabel =
                                                src.startsWith('google')
                                                    ? 'Google Maps'
                                                    : src == 'smart_engine'
                                                        ? 'Smart Engine'
                                                        : 'Estimated';
                                            ScaffoldMessenger.of(context)
                                                .hideCurrentSnackBar();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    backgroundColor:
                                                        Colors.green.shade700,
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                    duration: const Duration(
                                                        seconds: 4),
                                                    content: Text(
                                                        "âœ… $km km Â· â‚¹${res['diesel']} diesel Â· â‚¹${res['toll']} FASTag ($srcLabel)")));
                                          } else if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .hideCurrentSnackBar();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    backgroundColor:
                                                        Colors.orange.shade700,
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                    duration: const Duration(
                                                        seconds: 4),
                                                    content: Text(
                                                        "âš ï¸ Could not calculate. Please enter distance manually. (${res['source']})")));
                                          }
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  CitySearchField(
                                      label: "Unloading City",
                                      icon: Icons.location_city,
                                      iconColor: Colors.red,
                                      initialValue: prefillDestCity ?? '',
                                      onCitySelected: (city, state, pid) {
                                        setS(() {
                                          lDCity = city;
                                          lDState = state;
                                          lDCityPlaceId = pid;
                                        });
                                        // Auto-calc if origin is already known
                                        final orig = loFactName.isNotEmpty
                                            ? loFactName
                                            : lOCity;
                                        final oPid = loFactPlaceId.isNotEmpty
                                            ? loFactPlaceId
                                            : lOCityPlaceId;
                                        if (orig.isNotEmpty) {
                                          Future.delayed(
                                              const Duration(milliseconds: 300),
                                              () async {
                                            int ax = 6;
                                            try {
                                              if (selVeh != null) {
                                                ax = fleet
                                                    .firstWhere((v) =>
                                                        v.number == selVeh)
                                                    .axleCount;
                                              }
                                            } catch (_) {}
                                            final res =
                                                await RoutingEngine.calculate(
                                                    origin: orig,
                                                    destination: city,
                                                    axles: ax,
                                                    fuelEconomy:
                                                        double.tryParse(
                                                                feCtrl.text) ??
                                                            3.5,
                                                    originPlaceId: oPid,
                                                    destPlaceId: pid);
                                            if ((res['km'] as int? ?? 0) > 0) {
                                              setS(() {
                                                distCtrl.text =
                                                    res['km'].toString();
                                                tolCtrl.text =
                                                    res['toll'].toString();
                                                dslCtrl.text =
                                                    res['diesel'].toString();
                                                calcDone = true;
                                              });
                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        backgroundColor: Colors
                                                            .green.shade700,
                                                        behavior:
                                                            SnackBarBehavior
                                                                .floating,
                                                        duration:
                                                            const Duration(
                                                                seconds: 3),
                                                        content: Text(
                                                            "ðŸ“ ${res['km']} km Â· â‚¹${res['diesel']} diesel Â· â‚¹${res['toll']} toll")));
                                              }
                                            }
                                          });
                                        }
                                      }),
                                  if (lDState.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(
                                            top: 4, left: 4),
                                        child: Text(lDState,
                                            style: TextStyle(
                                                color: Colors.red[700],
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700))),
                                ])),
                        const SizedBox(height: 10),
                        TextField(
                            style: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                            controller: rCtrl,
                            decoration: InputDecoration(
                                labelText: "Full Route Description",
                                prefixIcon: const Icon(Icons.route, size: 16),
                                filled: true,
                                fillColor: const Color(0xFFFFF8E1),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00),
                                        width: 2)))),
                        const SizedBox(height: 12),

                        // Vehicle + Driver
                        Row(children: [
                          Expanded(
                              child: own == VehicleOwnership.self
                                  ? DropdownButtonFormField<String>(
                                      style: const TextStyle(
                                          color: Color(0xFF000000),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                      isExpanded: true,
                                      initialValue: selVeh,
                                      decoration: InputDecoration(
                                          labelText: "Fleet Vehicle",
                                          filled: true,
                                          fillColor: const Color(0xFFFFF8E1),
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: const BorderSide(
                                                  color: Color(0xFFFB8C00))),
                                          enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: const BorderSide(
                                                  color: Color(0xFFFB8C00))),
                                          focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: const BorderSide(
                                                  color:
                                                      Color(0xFFFB8C00),
                                                  width: 2))),
                                      items:
                                          fleet.map((v) => (v).number).toSet().map((n) => DropdownMenuItem<String>(value: n, child: Text(n, overflow: TextOverflow.ellipsis))).toList(),
                                      onChanged: (v) => setS(() => selVeh = v))
                                  : TextField(style: const TextStyle(color: Color(0xFF000000), fontSize: 14, fontWeight: FontWeight.w500), controller: vCtrl, decoration: InputDecoration(labelText: "Market Vehicle No.", filled: true, fillColor: const Color(0xFFFFF8E1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))))),
                          const SizedBox(width: 10),
                          if (own == VehicleOwnership.self)
                            Expanded(
                                child: DropdownButtonFormField<String>(
                                    style: const TextStyle(
                                        color: Color(0xFF000000),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500),
                                    decoration: InputDecoration(
                                        labelText: "Assign Driver",
                                        filled: true,
                                        fillColor: const Color(0xFFFFF8E1),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFFB8C00))),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFFB8C00))),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFFB8C00),
                                                width: 2))),
                                    items: drivers
                                        .map((d) => DropdownMenuItem<String>(value: (d).name, child: Text(d.name, overflow: TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (v) => setS(() => selDrv = v))),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  controller: ewCtrl,
                                  decoration: InputDecoration(
                                      labelText: "E-Way Bill No.",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00),
                                              width: 2))))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: TextField(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  controller: matCtrl,
                                  decoration: InputDecoration(
                                      labelText: "Material",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00),
                                              width: 2))))),
                        ]),
                        const SizedBox(height: 10),
                        // Material Invoice Number
                        TextField(
                            style: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                            controller: invCtrl,
                            decoration: InputDecoration(
                                labelText: "Material Invoice Number (optional)",
                                prefixIcon: const Icon(Icons.receipt_outlined,
                                    size: 16),
                                filled: true,
                                fillColor: const Color(0xFFFFF8E1),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00),
                                        width: 2)))),
                        const SizedBox(height: 12),
                        // Part Load Section
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Part Load Items",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: Color(0xFF000000))),
                              TextButton.icon(
                                onPressed: () {
                                  final nameC = TextEditingController();
                                  final invNoC = TextEditingController();
                                  final wtC = TextEditingController();
                                  String unit = "MT";
                                  showDialog(
                                      context: context,
                                      builder: (ctx2) => StatefulBuilder(
                                          builder: (ctx2, setD) => AlertDialog(
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16)),
                                                title: const Text(
                                                    "Add Part Load Item",
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 15)),
                                                content: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      TextField(
                                                          style: const TextStyle(
                                                              color: Color(
                                                                  0xFFF2EDE4),
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500),
                                                          controller: nameC,
                                                          decoration: InputDecoration(
                                                              labelText:
                                                                  "Material Name *",
                                                              filled: true,
                                                              fillColor: const Color(
                                                                  0xFF243D2E),
                                                              border: OutlineInputBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                          10),
                                                                  borderSide:
                                                                      const BorderSide(
                                                                          color: Color(
                                                                              0xFF3D5A47))),
                                                              enabledBorder: OutlineInputBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                          10),
                                                                  borderSide:
                                                                      const BorderSide(
                                                                          color: Color(0xFFFB8C00))),
                                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2)))),
                                                      const SizedBox(
                                                          height: 10),
                                                      TextField(
                                                          style: const TextStyle(
                                                              color: Color(
                                                                  0xFFF2EDE4),
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500),
                                                          controller: invNoC,
                                                          decoration: InputDecoration(
                                                              labelText:
                                                                  "Invoice Number",
                                                              filled: true,
                                                              fillColor: const Color(
                                                                  0xFF243D2E),
                                                              border: OutlineInputBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                          10),
                                                                  borderSide:
                                                                      const BorderSide(
                                                                          color: Color(
                                                                              0xFF3D5A47))),
                                                              enabledBorder: OutlineInputBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                          10),
                                                                  borderSide:
                                                                      const BorderSide(
                                                                          color: Color(0xFFFB8C00))),
                                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2)))),
                                                      const SizedBox(
                                                          height: 10),
                                                      Row(children: [
                                                        Expanded(
                                                            child: TextField(
                                                                style: const TextStyle(
                                                                    color: Color(
                                                                        0xFFF2EDE4),
                                                                    fontSize:
                                                                        14,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500),
                                                                controller: wtC,
                                                                keyboardType:
                                                                    TextInputType
                                                                        .number,
                                                                decoration: InputDecoration(
                                                                    labelText:
                                                                        "Weight *",
                                                                    filled:
                                                                        true,
                                                                    fillColor:
                                                                        const Color(
                                                                            0xFF243D2E),
                                                                    border: OutlineInputBorder(
                                                                        borderRadius: BorderRadius.circular(
                                                                            10),
                                                                        borderSide: const BorderSide(
                                                                            color: Color(
                                                                                0xFF3D5A47))),
                                                                    enabledBorder: OutlineInputBorder(
                                                                        borderRadius: BorderRadius.circular(10),
                                                                        borderSide: const BorderSide(color: Color(0xFFFB8C00))),
                                                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))))),
                                                        const SizedBox(
                                                            width: 8),
                                                        StatefulBuilder(
                                                            builder: (_, ss) => DropdownButton<
                                                                    String>(
                                                                value: unit,
                                                                items: [
                                                                  "MT",
                                                                  "KG",
                                                                  "L",
                                                                  "KL"
                                                                ]
                                                                    .map((u) => DropdownMenuItem(
                                                                        value:
                                                                            u,
                                                                        child: Text(
                                                                            u)))
                                                                    .toList(),
                                                                onChanged: (v) {
                                                                  ss(() =>
                                                                      unit =
                                                                          v!);
                                                                })),
                                                      ]),
                                                    ]),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(ctx2),
                                                      child:
                                                          const Text("Cancel")),
                                                  ElevatedButton(
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFF0D1F14)),
                                                      onPressed: () {
                                                        if (nameC
                                                                .text.isEmpty ||
                                                            wtC.text.isEmpty) {
                                                          return;
                                                        }
                                                        setS(() => partItems
                                                            .add(InvoiceItem(
                                                                materialName:
                                                                    nameC.text,
                                                                invoiceNo:
                                                                    invNoC.text,
                                                                weight: double
                                                                        .tryParse(wtC
                                                                            .text) ??
                                                                    0,
                                                                weightUnit:
                                                                    unit)));
                                                        Navigator.pop(ctx2);
                                                      },
                                                      child: const Text("Add",
                                                          style: TextStyle(
                                                              color: Color(
                                                                  0xFFF2EDE4)))),
                                                ],
                                              )));
                                },
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 14),
                                label: const Text("Add Item",
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ]),
                        if (partItems.isNotEmpty)
                          ...partItems.asMap().entries.map((e) => Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.blue.shade100)),
                              child: Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(e.value.materialName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: Color(0xFF000000))),
                                      Text(
                                          "${e.value.weight} ${e.value.weightUnit}${e.value.invoiceNo.isNotEmpty ? ' | Inv: ${e.value.invoiceNo}' : ''}",
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey)),
                                    ])),
                                IconButton(
                                    icon: const Icon(Icons.close,
                                        size: 16, color: Colors.red),
                                    onPressed: () =>
                                        setS(() => partItems.removeAt(e.key))),
                              ]))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: StatefulBuilder(
                                  builder: (wCtx, wSt) => Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            TextField(
                                                controller: wtCtrl,
                                                keyboardType:
                                                    TextInputType.number,
                                                onChanged: (_) => wSt(() {}),
                                                decoration: InputDecoration(
                                                    labelText: "Weight (Tons)",
                                                    prefixIcon: const Icon(
                                                        Icons.scale,
                                                        size: 18),
                                                    suffixIcon: prefillWeight != null && prefillWeight > 0 && (double.tryParse(wtCtrl.text) ?? 0) != prefillWeight
                                                        ? const Tooltip(
                                                            message:
                                                                "Weight differs from posted",
                                                            child: Icon(Icons.warning_amber,
                                                                color: Colors
                                                                    .orange,
                                                                size: 18))
                                                        : null,
                                                    filled: true,
                                                    fillColor:
                                                        const Color(0xFFFFF8E1),
                                                    labelStyle: const TextStyle(
                                                        color: Color(
                                                            0xFF8FBC8F),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w500),
                                                    floatingLabelStyle: const TextStyle(
                                                        color: Color(0xFFFB8C00),
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 12),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00))),
                                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00))),
                                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2)))),
                                            if (prefillWeight != null &&
                                                prefillWeight > 0)
                                              Text(
                                                  "Posted: ${prefillWeight}T â€” edit if actual differs",
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey)),
                                          ]))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: DropdownButtonFormField<String>(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  initialValue: wUnit,
                                  decoration: InputDecoration(
                                      labelText: "Unit",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00),
                                              width: 2))),
                                  items: ["MT", "KG", "LT", "TON"]
                                      .map((u) =>
                                          DropdownMenuItem(value: u, child: Text(u)))
                                      .toList(),
                                  onChanged: (v) => setS(() => wUnit = v!))),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  controller: fCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                      labelText: "Total Freight Billed (â‚¹) *",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00),
                                              width: 2))))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: TextField(
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                  controller: rcvdCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                      labelText: "Advance Received (â‚¹)",
                                      filled: true,
                                      fillColor: const Color(0xFFFFF8E1),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFFB8C00),
                                              width: 2))))),
                        ]),
                        const SizedBox(height: 12),

                        // GST
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.indigo[50],
                                borderRadius: BorderRadius.circular(12)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("GST Configuration",
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.indigo,
                                          fontSize: 13)),
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    Expanded(
                                        child: DropdownButtonFormField<GstType>(
                                            style: const TextStyle(
                                                color: Color(0xFF000000),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500),
                                            initialValue: gst,
                                            decoration: InputDecoration(
                                                labelText: "GST Type",
                                                isDense: true,
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFFFF8E1),
                                                border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    borderSide: const BorderSide(
                                                        color:
                                                            Color(0xFFFB8C00))),
                                                enabledBorder: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    borderSide: const BorderSide(
                                                        color:
                                                            Color(0xFFFB8C00))),
                                                focusedBorder: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))),
                                            items: const [
                                              DropdownMenuItem(
                                                  value: GstType.none,
                                                  child: Text("None")),
                                              DropdownMenuItem(
                                                  value: GstType.cgstSgst,
                                                  child: Text("CGST+SGST")),
                                              DropdownMenuItem(
                                                  value: GstType.igst,
                                                  child: Text("IGST"))
                                            ],
                                            onChanged: (v) => setS(() => gst = v!))),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: DropdownButtonFormField<double>(
                                            style: const TextStyle(
                                                color: Color(0xFF000000),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500),
                                            initialValue: gstRate,
                                            decoration: InputDecoration(
                                                labelText: "Rate %",
                                                isDense: true,
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFFFF8E1),
                                                border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(
                                                        8),
                                                    borderSide: const BorderSide(
                                                        color:
                                                            Color(0xFFFB8C00))),
                                                enabledBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(
                                                        8),
                                                    borderSide: const BorderSide(
                                                        color:
                                                            Color(0xFFFB8C00))),
                                                focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))),
                                            items: [5.0, 12.0, 18.0, 28.0].map((r) => DropdownMenuItem(value: r, child: Text("$r%"))).toList(),
                                            onChanged: (v) => setS(() => gstRate = v!))),
                                  ]),
                                  SwitchListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                          "Freight is GST-inclusive",
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                      value: gstInc,
                                      activeThumbColor: Colors.indigo,
                                      onChanged: (v) => setS(() => gstInc = v)),
                                ])),
                        const SizedBox(height: 12),

                        // Deductions
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Deductions",
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.red,
                                          fontSize: 13)),
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    Expanded(child:
                                        StatefulBuilder(builder: (ctx, setTDS) {
                                      void recalcTDS() {
                                        final pct =
                                            double.tryParse(tdsCtrl.text) ?? 0;
                                        final freight =
                                            double.tryParse(fCtrl.text) ?? 0;
                                        final amt = (freight * pct / 100);
                                        setTDS(
                                            () {}); // trigger rebuild to show auto-amount
                                      }

                                      tdsCtrl.addListener(recalcTDS);
                                      final pct =
                                          double.tryParse(tdsCtrl.text) ?? 0;
                                      final freight =
                                          double.tryParse(fCtrl.text) ?? 0;
                                      final tdsAmt = freight * pct / 100;
                                      return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            TextField(
                                                controller: tdsCtrl,
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration: InputDecoration(
                                                    labelText: "TDS %",
                                                    hintText: "2 (for 2%)",
                                                    prefixIcon: const Icon(
                                                        Icons.percent,
                                                        size: 18),
                                                    filled: true,
                                                    fillColor:
                                                        const Color(0xFFFFF8E1),
                                                    border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8)))),
                                            if (tdsAmt > 0)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4, left: 4),
                                                  child: Text(
                                                      "TDS Amount: â‚¹${tdsAmt.toStringAsFixed(0)}",
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              Colors.red[700],
                                                          fontWeight: FontWeight
                                                              .w700))),
                                          ]);
                                    })),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: TextField(
                                            style: const TextStyle(
                                                color: Color(0xFF000000),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500),
                                            controller: penCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                                labelText: "Penalties (â‚¹)",
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFFFF8E1),
                                                border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(
                                                        8),
                                                    borderSide: const BorderSide(
                                                        color:
                                                            Color(0xFFFB8C00))),
                                                enabledBorder: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    borderSide: const BorderSide(
                                                        color:
                                                            Color(0xFFFB8C00))),
                                                focusedBorder: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))))),
                                  ]),
                                ])),
                        const SizedBox(height: 12),

                        // Market payables
                        if (own == VehicleOwnership.market)
                          Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Market Vehicle Payables",
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: Colors.purple)),
                                    const SizedBox(height: 10),
                                    Row(children: [
                                      Expanded(
                                          child: TextField(
                                              style: const TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500),
                                              controller: mfCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: InputDecoration(
                                                  labelText:
                                                      "Freight for Truck",
                                                  filled: true,
                                                  fillColor:
                                                      const Color(0xFFFFF8E1),
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: Color(
                                                                  0xFF3D5A47))),
                                                  enabledBorder: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: const BorderSide(
                                                          color:
                                                              Color(0xFFFB8C00))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))))),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: TextField(
                                              style: const TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500),
                                              controller: maCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: InputDecoration(
                                                  labelText: "Advance Paid",
                                                  filled: true,
                                                  fillColor:
                                                      const Color(0xFFFFF8E1),
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: Color(
                                                                  0xFF3D5A47))),
                                                  enabledBorder: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: const BorderSide(
                                                          color:
                                                              Color(0xFFFB8C00))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2)))))
                                    ]),
                                  ])),

                        // Self expenses
                        if (own == VehicleOwnership.self)
                          Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text("Self Vehicle Expenses",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.orange,
                                                  fontSize: 14)),
                                          TextButton.icon(
                                            onPressed: () async {
                                              // Priority: factory placeId > factory name > city placeId > city name
                                              final origin =
                                                  loFactName.isNotEmpty
                                                      ? loFactName
                                                      : (lOCity.isNotEmpty
                                                          ? lOCity
                                                          : rCtrl.text
                                                              .split('â†’')
                                                              .first
                                                              .trim());
                                              final dest = ldFactName.isNotEmpty
                                                  ? ldFactName
                                                  : (lDCity.isNotEmpty
                                                      ? lDCity
                                                      : rCtrl.text
                                                          .split('â†’')
                                                          .last
                                                          .trim());
                                              final oPid =
                                                  loFactPlaceId.isNotEmpty
                                                      ? loFactPlaceId
                                                      : lOCityPlaceId;
                                              final dPid =
                                                  ldFactPlaceId.isNotEmpty
                                                      ? ldFactPlaceId
                                                      : lDCityPlaceId;
                                              if (origin.isEmpty) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(const SnackBar(
                                                        content: Text(
                                                            "Enter loading factory or city first")));
                                                return;
                                              }
                                              final srcHint = loFactPlaceId
                                                      .isNotEmpty
                                                  ? "factory GPS coordinates"
                                                  : lOCityPlaceId.isNotEmpty
                                                      ? "city coordinates"
                                                      : "name search";
                                              showDialog(
                                                  context: context,
                                                  barrierDismissible: false,
                                                  builder: (_) => Center(
                                                      child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(24),
                                                          decoration: BoxDecoration(
                                                              color: const Color(
                                                                  0xFFF2EDE4),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          16)),
                                                          child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                const CircularProgressIndicator(
                                                                    color: Color(
                                                                        0xFFF2EDE4)),
                                                                const SizedBox(
                                                                    height: 12),
                                                                Text(
                                                                    "Calculating via $srcHint...",
                                                                    style: const TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                        fontWeight:
                                                                            FontWeight.w600))
                                                              ]))));
                                              int axles = 6;
                                              if (selVeh != null) {
                                                try {
                                                  axles = fleet
                                                      .firstWhere((v) =>
                                                          v.number == selVeh)
                                                      .axleCount;
                                                } catch (_) {}
                                              }
                                              final fe = double.tryParse(
                                                      feCtrl.text) ??
                                                  3.5;
                                              final res =
                                                  await RoutingEngine.calculate(
                                                      origin: origin,
                                                      destination: dest,
                                                      axles: axles,
                                                      fuelEconomy: fe,
                                                      originPlaceId: oPid,
                                                      destPlaceId: dPid);
                                              if (mounted) {
                                                Navigator.pop(context);
                                              }
                                              setS(() {
                                                distCtrl.text =
                                                    res['km'].toString();
                                                tolCtrl.text =
                                                    res['toll'].toString();
                                                dslCtrl.text =
                                                    res['diesel'].toString();
                                                calcDone = true;
                                              });
                                              final src =
                                                  res['source'] ?? 'offline';
                                              final km0 =
                                                  (res['km'] as int? ?? 0);
                                              if (km0 == 0) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        backgroundColor:
                                                            Colors.orange,
                                                        behavior:
                                                            SnackBarBehavior
                                                                .floating,
                                                        duration:
                                                            const Duration(
                                                                seconds: 5),
                                                        content: const Text(
                                                            "Route not found in database. Enable Google Maps API for local/precise distances.")));
                                              } else {
                                                final srcLabel = src == 'google'
                                                    ? 'Google Maps'
                                                    : src.startsWith('api_err')
                                                        ? 'API Error - $src'
                                                        : 'Smart Engine';
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        backgroundColor:
                                                            Colors.green[800],
                                                        behavior:
                                                            SnackBarBehavior
                                                                .floating,
                                                        duration:
                                                            const Duration(
                                                                seconds: 4),
                                                        content: Text(
                                                            "$km0 km | Diesel: Rs.${res['diesel']} | $axles-axle FASTag Rs.${res['toll']} | $srcLabel")));
                                              }
                                            },
                                            icon: const Icon(
                                                Icons.auto_fix_high,
                                                size: 14,
                                                color: Colors.blueAccent),
                                            label: const Text(
                                                "Auto-calc from Maps",
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.blueAccent,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ]),
                                    const SizedBox(height: 8),
                                    if (calcDone)
                                      Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                              color: Colors.green
                                                  .withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: Colors.green[200]!)),
                                          child: Text(
                                              "âœ“ Route calculated via ${AppConfig.googleMapsApiKey.isEmpty ? 'Smart Engine' : 'Google Maps'}",
                                              style: TextStyle(
                                                  color: Colors.green[800],
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w700))),
                                    Row(children: [
                                      Expanded(
                                          child: TextField(
                                              style: const TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500),
                                              controller: distCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: InputDecoration(
                                                  labelText: "Distance (km)",
                                                  prefixIcon: const Icon(
                                                      Icons.route,
                                                      size: 16,
                                                      color: Colors.blueAccent),
                                                  filled: true,
                                                  fillColor:
                                                      const Color(0xFFFFF8E1),
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: const BorderSide(
                                                          color: Color(
                                                              0xFF3D5A47))),
                                                  enabledBorder: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(color: Color(0xFFFB8C00))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))))),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: TextField(
                                              style: const TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500),
                                              controller: feCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: InputDecoration(
                                                  labelText: "Mileage (kmpl)",
                                                  prefixIcon: const Icon(
                                                      Icons.local_gas_station,
                                                      size: 16,
                                                      color: Colors.orange),
                                                  filled: true,
                                                  fillColor:
                                                      const Color(0xFFFFF8E1),
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: Color(
                                                                  0xFF3D5A47))),
                                                  enabledBorder: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                      borderSide: const BorderSide(color: Color(0xFFFB8C00))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))))),
                                    ]),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      Expanded(
                                          child: TextField(
                                              style: const TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500),
                                              controller: dslCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: InputDecoration(
                                                  labelText: "Diesel (â‚¹)",
                                                  filled: true,
                                                  fillColor:
                                                      const Color(0xFFFFF8E1),
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: Color(
                                                                  0xFF3D5A47))),
                                                  enabledBorder: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: const BorderSide(
                                                          color:
                                                              Color(0xFFFB8C00))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2))))),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: TextField(
                                              style: const TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500),
                                              controller: tolCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: InputDecoration(
                                                  labelText: "Toll/FASTag (â‚¹)",
                                                  filled: true,
                                                  fillColor:
                                                      const Color(0xFFFFF8E1),
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: const BorderSide(
                                                          color: Color(
                                                              0xFF3D5A47))),
                                                  enabledBorder: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: Color(
                                                                  0xFF3D5A47))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 2)))))
                                    ]),
                                    const SizedBox(height: 8),
                                    TextField(
                                        style: const TextStyle(
                                            color: Color(0xFF000000),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                        controller: drvCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                            labelText: "Driver Expenses (â‚¹)",
                                            prefixIcon: const Icon(Icons.person,
                                                size: 18),
                                            filled: true,
                                            fillColor: const Color(0xFFFFF8E1),
                                            border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFFFB8C00))),
                                            enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFFFB8C00))),
                                            focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                    color:
                                                        Color(0xFFFB8C00),
                                                    width: 2)))),
                                  ])),
                        const SizedBox(height: 12),
                        TextField(
                            style: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                            controller: notCtrl,
                            maxLines: 2,
                            decoration: InputDecoration(
                                labelText: "LR Notes / Remarks",
                                filled: true,
                                fillColor: const Color(0xFFFFF8E1),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00),
                                        width: 2)))),
                        const SizedBox(height: 22),
                        SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFB8C00),
                                  foregroundColor: const Color(0xFFFFF8E1),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14)),
                              onPressed: () {
                                double f = double.tryParse(fCtrl.text) ?? 0;
                                if (f <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text("Enter freight amount"),
                                          backgroundColor: Colors.red));
                                  return;
                                }
                                double rc = double.tryParse(rcvdCtrl.text) ?? 0;
                                double pen = double.tryParse(penCtrl.text) ?? 0;
                                final tdsPct =
                                    double.tryParse(tdsCtrl.text) ?? 0;
                                final double tds =
                                    (double.tryParse(fCtrl.text) ?? 0) *
                                        tdsPct /
                                        100;
                                double dist =
                                    double.tryParse(distCtrl.text) ?? 0;
                                double fe = double.tryParse(feCtrl.text) ?? 3.5;
                                double wt = double.tryParse(wtCtrl.text) ?? 0;
                                double dsl = 0,
                                    tol = 0,
                                    drv = 0,
                                    los = 0,
                                    mfr = 0,
                                    ma = 0;
                                String finalVeh = own == VehicleOwnership.self
                                    ? (selVeh ?? "Unassigned")
                                    : vCtrl.text;
                                if (own == VehicleOwnership.self) {
                                  dsl = double.tryParse(dslCtrl.text) ?? 0;
                                  if (dsl == 0 && dist > 0 && fe > 0) {
                                    dsl = (dist / fe) *
                                        AppConfig.defaultDieselPrice;
                                  }
                                  tol = double.tryParse(tolCtrl.text) ?? 0;
                                  drv = double.tryParse(drvCtrl.text) ?? 0;
                                  los = double.tryParse(losCtrl.text) ?? 0;
                                } else {
                                  mfr = double.tryParse(mfCtrl.text) ?? 0;
                                  ma = double.tryParse(maCtrl.text) ?? 0;
                                }

                                final newL = TripLedger(
                                    id: "TRP${math.Random().nextInt(99999)}",
                                    date:
                                        "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
                                    partyName: pCtrl.text.isEmpty
                                        ? "Unknown Party"
                                        : pCtrl.text,
                                    vehicleNo: finalVeh,
                                    route: rCtrl.text.isNotEmpty
                                        ? rCtrl.text
                                        : "${loFactName.isNotEmpty ? loFactName : lOCity} â†’ ${ldFactName.isNotEmpty ? ldFactName : lDCity}",
                                    ownership: own,
                                    eWayBillNo: ewCtrl.text.isNotEmpty
                                        ? ewCtrl.text
                                        : "PENDING",
                                    materialName: matCtrl.text.isNotEmpty
                                        ? matCtrl.text
                                        : "General",
                                    loadingPoint: loFactName.isNotEmpty
                                        ? loFactName
                                        : lOCity,
                                    unloadingPoint: ldFactName.isNotEmpty
                                        ? ldFactName
                                        : lDCity,
                                    loadingState: lOState,
                                    unloadingState: lDState,
                                    consignorPhone: cpCtrl.text,
                                    consignorEmail: ceCtrl.text,
                                    consignorGstin: cgCtrl.text,
                                    freightBilled: f,
                                    paymentReceived: rc,
                                    diesel: dsl,
                                    toll: tol,
                                    driverExp: drv,
                                    materialLoss: los,
                                    marketTruckFreight: mfr,
                                    marketAdvancePaid: ma,
                                    penalties: pen,
                                    tdsDeduction: tds,
                                    distanceKm: dist,
                                    fuelEconomy: fe,
                                    driverName: selDrv,
                                    paymentTermsDays:
                                        int.tryParse(tmCtrl.text) ?? 30,
                                    lrNotes: notCtrl.text,
                                    gstType: gst,
                                    gstRate: gstRate,
                                    isGstInclusive: gstInc,
                                    weightTons: wt,
                                    weightUnit: wUnit,
                                    platformCommission: f * 0.02,
                                    consignorCommission: f * 0.02,
                                    materialInvoiceNo: invCtrl.text.trim(),
                                    invoiceItems:
                                        List<InvoiceItem>.from(partItems));

                                setState(() {
                                  ledgers.insert(0, newL);
                                  subscription.tripsUsedThisMonth++;
                                });
                                _save();
                                Navigator.pop(ctx);
                                // Auto-share docs if consignor email provided
                                if (ceCtrl.text.isNotEmpty &&
                                    own == VehicleOwnership.self &&
                                    selVeh != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          backgroundColor: Colors.blue,
                                          behavior: SnackBarBehavior.floating,
                                          content: Text(
                                              "âœ… Ledger saved! Vehicle docs auto-compiled for ${ceCtrl.text}")));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          backgroundColor: Colors.green,
                                          behavior: SnackBarBehavior.floating,
                                          content:
                                              Text("âœ… Ledger entry saved!")));
                                }
                              },
                              child: const Text("Save Dispatch Ledger",
                                  style: TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold)),
                            )),
                        const SizedBox(height: 30),
                      ])),
                )));
  }

  // Helper for TextDecoration in forms (avoiding typo)

  // â”€â”€ FLEET TAB â”€â”€
  Widget _buildFleet() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Fleet Assets",
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF000000))),
          ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF8E1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: _addVehicle,
              icon: const Icon(Icons.add,
                  color: Color(0xFF000000), size: 16),
              label: const Text("Add Vehicle",
                  style:
                      TextStyle(color: Color(0xFF000000), fontSize: 12)))
        ]),
        const SizedBox(height: 20),
        ...fleet.map((a) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: const Color(0xFF000000),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 15)
                ]),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ExpansionTile(
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                            color: Color(0xFFFB8C00),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.local_shipping,
                            color: Color(0xFF000000), size: 22)),
                    title: Text(a.number,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Color(0xFF000000),
                            letterSpacing: 0.5)),
                    subtitle: Wrap(spacing: 4, runSpacing: 4, children: [
                      _chip(Icons.directions_car_outlined, a.type,
                          const Color(0xFFFB8C00)),
                      _chip(Icons.settings_outlined, "${a.axleCount}ax",
                          const Color(0xFFFB8C00)),
                      _chip(
                          Icons.scale_outlined,
                          a.payload.length > 6
                              ? a.payload.substring(0, 6)
                              : a.payload,
                          const Color(0xFFFB8C00)),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      GestureDetector(
                          onTap: () {
                            if (!subscription.canUseGPS) {
                              _upgradeBanner("Vehicle GPS Tracking");
                              return;
                            }
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => LiveTrackingScreen(
                                        route: "Active Route",
                                        vehicleNo: a.number)));
                          },
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.green[200]!)),
                              child: Row(children: [
                                Icon(Icons.gps_fixed_rounded,
                                    size: 12, color: Colors.green[700]),
                                const SizedBox(width: 4),
                                Text("Track",
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold))
                              ]))),
                      const SizedBox(width: 6),
                      const Icon(Icons.expand_more),
                    ]),
                    children: [
                      Container(
                          padding: const EdgeInsets.all(20),
                          color: const Color(0xFF000000),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Compliance vault
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Compliance Vault",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF000000),
                                              fontSize: 13)),
                                      Text(
                                          "${a.docs.where((d) => d.isUploaded).length}/${a.docs.length} uploaded",
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: a.docs.every(
                                                      (d) => d.isUploaded)
                                                  ? Colors.green
                                                  : Colors.orange,
                                              fontWeight: FontWeight.bold))
                                    ]),
                                const SizedBox(height: 12),
                                ...a.docs.map((d) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                            color: d.isUploaded
                                                ? Colors.green[50]
                                                : Colors.orange[50],
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: d.isUploaded
                                                    ? Colors.green[200]!
                                                    : Colors.orange[200]!)),
                                        child: Row(children: [
                                          Icon(
                                              d.isUploaded
                                                  ? Icons.check_circle
                                                  : Icons.warning_amber,
                                              color: d.isUploaded
                                                  ? Colors.green
                                                  : Colors.orange,
                                              size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(d.name,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13)),
                                                Text(
                                                    d.isUploaded
                                                        ? "Expires: ${d.expiryDate}"
                                                        : "Not Uploaded",
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: d.isUploaded
                                                            ? Colors.grey
                                                            : Colors.orange))
                                              ])),
                                          Row(children: [
                                            if (d.isUploaded &&
                                                d.filePath.isNotEmpty)
                                              IconButton(
                                                  icon: const Icon(
                                                      Icons.visibility,
                                                      size: 18,
                                                      color: Colors.teal),
                                                  tooltip: "View Document",
                                                  onPressed: () =>
                                                      _viewFleetDoc(d)),
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.camera_alt,
                                                    size: 18,
                                                    color: Colors.blue),
                                                tooltip: "Camera",
                                                onPressed: () =>
                                                    _uploadDocWithMethod(
                                                        d,
                                                        a,
                                                        DocUploadMethod
                                                            .camera)),
                                            IconButton(
                                                icon: const Icon(
                                                    Icons.upload_file,
                                                    size: 18,
                                                    color: Colors.indigo),
                                                tooltip: "Upload File",
                                                onPressed: () =>
                                                    _uploadDocWithMethod(d, a,
                                                        DocUploadMethod.file)),
                                          ]),
                                        ])))),

                                // Batteries
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Battery Records",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF000000),
                                              fontSize: 13)),
                                      TextButton.icon(
                                          icon: const Icon(Icons.add, size: 14),
                                          label: const Text("Add Battery"),
                                          onPressed: () => _addBattery(a))
                                    ]),
                                if (a.batteries.isEmpty)
                                  const Text("No battery records",
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                ...a.batteries.map((b) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: Colors.yellow[50],
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.yellow[300]!)),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text("${b.make} ${b.model}",
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 13)),
                                                Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                        color:
                                                            Colors.green[100],
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6)),
                                                    child: Text(
                                                        "${b.warrantyYears}yr Warranty",
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors
                                                                .green[800],
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)))
                                              ]),
                                          const SizedBox(height: 4),
                                          Text("Serial: ${b.serialNo}",
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11)),
                                          Text(
                                              "Bill No: ${b.billNo.isNotEmpty ? b.billNo : 'N/A'}",
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11)),
                                          Text(
                                              "Purchase: ${b.purchaseDate} | Warranty till: ${b.warrantyExpiry}",
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11)),
                                        ]))),

                                const SizedBox(height: 8),
                                Row(children: [
                                  Expanded(
                                      child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                              side: const BorderSide(
                                                  color:
                                                      Color(0xFF000000))),
                                          onPressed: () => _editAsset(a),
                                          icon: const Icon(Icons.build,
                                              size: 16,
                                              color: Color(0xFF000000)),
                                          label: const Text("Edit Tyres",
                                              style: TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontSize: 12)))),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.teal,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10))),
                                          onPressed: () => _sendVehicleDocs(a),
                                          icon: const Icon(Icons.send,
                                              size: 14,
                                              color: Color(0xFF000000)),
                                          label: const Text("Send Docs Bundle",
                                              style: TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontSize: 12)))),
                                ]),
                              ]))
                    ])))),
      ]);

  // Simple upload confirmation dialog (no external package required)
  void _showDocUploadDialog(BuildContext ctx, String docName) {
    final dateCtrl = TextEditingController();
    showDialog(
        context: ctx,
        builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(children: [
                const Icon(Icons.check_circle_outline, color: Colors.green),
                const SizedBox(width: 8),
                Flexible(
                    child: Text("Upload $docName",
                        overflow: TextOverflow.ellipsis))
              ]),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Row(children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Flexible(
                          child: Text(
                              "Document marked as uploaded. Enter expiry date below.",
                              style:
                                  TextStyle(fontSize: 12, color: Colors.green)))
                    ])),
                const SizedBox(height: 12),
                TextField(
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    controller: dateCtrl,
                    decoration: InputDecoration(
                        labelText: "Expiry Date (DD/MM/YYYY)",
                        hintText: "e.g. 31/12/2026",
                        prefixIcon: const Icon(Icons.calendar_today, size: 18),
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2)))),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text("Cancel")),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF8E1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      Navigator.pop(c);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                              "âœ… $docName uploaded${dateCtrl.text.isNotEmpty ? ' â€” Expiry: ${dateCtrl.text}' : ''}!")));
                    },
                    child: const Text("Confirm",
                        style: TextStyle(color: Color(0xFF000000)))),
              ],
            ));
  }

  Future<void> _uploadDocWithMethod(
      FleetDoc doc, Asset asset, DocUploadMethod method) async {
    String? pickedPath;
    String? pickedName;
    String pickedMime = 'image/jpeg';
    Map<String, String> extracted = {};
    bool isOCRing = false;

    try {
      if (method == DocUploadMethod.camera) {
        final img = await ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 95,
            maxWidth: 2048,
            maxHeight: 2048);
        if (img != null) {
          pickedPath = img.path;
          pickedName = img.name;
          pickedMime = 'image/jpeg';
        }
      } else {
        final res = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
            withData: false);
        if (res != null && res.files.isNotEmpty) {
          pickedPath = res.files.single.path;
          pickedName = res.files.single.name;
          pickedMime = pickedName.endsWith('.pdf') == true
              ? 'application/pdf'
              : 'image/jpeg';
        }
      }
    } catch (_) {}

    // Run OCR on picked image before showing dialog
    if (pickedPath != null && pickedMime.startsWith('image')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF000000))),
              SizedBox(width: 12),
              Text("Reading document...")
            ]),
            backgroundColor: Colors.indigo,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 8)));
      }
      extracted = await FirebaseService.extractDocumentText(pickedPath);
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    if (!mounted) return;

    // Pre-fill from OCR extraction, fall back to existing stored values
    final dateCtrl = TextEditingController(
        text: extracted['expiryDate'] ??
            (doc.expiryDate == 'Pending' ? '' : doc.expiryDate));
    final engineCtrl =
        TextEditingController(text: extracted['engineNo'] ?? doc.engineNo);
    final chassisCtrl =
        TextEditingController(text: extracted['chassisNo'] ?? doc.chassisNo);
    final regCtrl =
        TextEditingController(text: extracted['regNo'] ?? doc.regNo);
    final insurerCtrl =
        TextEditingController(text: extracted['insurer'] ?? doc.insurer);
    final remarksCtrl = TextEditingController(text: doc.remarks);
    final ownerCtrl =
        TextEditingController(text: extracted['ownerName'] ?? doc.ownerName);
    final wasOCRed = extracted.isNotEmpty && !extracted.containsKey('error');

    // Determine which extra fields to show based on doc type
    final isRC = doc.name.toLowerCase().contains('rc') ||
        doc.name.toLowerCase().contains('registration');
    final isIns = doc.name.toLowerCase().contains('insurance');
    final isPUCC = doc.name.toLowerCase().contains('pucc') ||
        doc.name.toLowerCase().contains('pollution');

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              title: Row(children: [
                Icon(
                    pickedPath != null
                        ? Icons.check_circle
                        : Icons.edit_document,
                    color: pickedPath != null
                        ? Colors.green
                        : const Color(0xFFFFF8E1)),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(doc.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis)),
              ]),
              content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        // File chip
                        if (pickedPath != null)
                          Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.green.shade200)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Icon(
                                          pickedMime == 'application/pdf'
                                              ? Icons.picture_as_pdf
                                              : Icons.image,
                                          color: Colors.green,
                                          size: 18),
                                      const SizedBox(width: 8),
                                      Flexible(
                                          child: Text(
                                              pickedName ?? 'File selected',
                                              style: const TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12),
                                              overflow: TextOverflow.ellipsis)),
                                    ]),
                                    if (wasOCRed)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Row(children: [
                                            const Icon(Icons.auto_awesome,
                                                color: Colors.indigo, size: 13),
                                            const SizedBox(width: 4),
                                            Text(
                                                "${extracted.length} fields auto-read from document",
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.indigo,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ])),
                                  ]))
                        else
                          Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Text(
                                  "No file â€” fill details manually",
                                  style: TextStyle(
                                      color: Colors.amber, fontSize: 12))),
                        // Expiry date (always)
                        TextField(
                            style: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                            controller: dateCtrl,
                            decoration: InputDecoration(
                                labelText: "Expiry Date (DD/MM/YYYY)",
                                hintText: "31/12/2026",
                                prefixIcon:
                                    const Icon(Icons.calendar_today, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFFFF8E1),
                                labelStyle: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                                floatingLabelStyle: const TextStyle(
                                    color: Color(0xFFFB8C00),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00),
                                        width: 2)))),
                        // RC-specific fields
                        if (isRC) ...[
                          const SizedBox(height: 10),
                          TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: regCtrl,
                              decoration: InputDecoration(
                                  labelText: "Registration Number",
                                  hintText: "GJ-01-WT-1000",
                                  prefixIcon: const Icon(
                                      Icons.confirmation_number,
                                      size: 18),
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2)))),
                          const SizedBox(height: 10),
                          TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: engineCtrl,
                              decoration: InputDecoration(
                                  labelText: "Engine Number",
                                  hintText: "e.g. WO6EATG12345",
                                  prefixIcon:
                                      const Icon(Icons.settings, size: 18),
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2)))),
                          const SizedBox(height: 10),
                          TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: chassisCtrl,
                              decoration: InputDecoration(
                                  labelText: "Chassis / VIN Number",
                                  hintText: "17-char VIN",
                                  prefixIcon: const Icon(Icons.tag, size: 18),
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2)))),
                          const SizedBox(height: 10),
                          TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: ownerCtrl,
                              decoration: InputDecoration(
                                  labelText: "Owner Name",
                                  hintText: "As per RC",
                                  prefixIcon:
                                      const Icon(Icons.person, size: 18),
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2)))),
                        ],
                        // Insurance-specific fields
                        if (isIns) ...[
                          const SizedBox(height: 10),
                          TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: insurerCtrl,
                              decoration: InputDecoration(
                                  labelText: "Insurance Company",
                                  hintText: "e.g. New India Assurance",
                                  prefixIcon:
                                      const Icon(Icons.business, size: 18),
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2)))),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                            style: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                            controller: remarksCtrl,
                            decoration: InputDecoration(
                                labelText: "Remarks (optional)",
                                hintText: "Policy no., notes...",
                                filled: true,
                                fillColor: const Color(0xFFFFF8E1),
                                labelStyle: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                                floatingLabelStyle: const TextStyle(
                                    color: Color(0xFFFB8C00),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00),
                                        width: 2)))),
                      ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text("Cancel")),
                ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF8E1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10)),
                    icon: const Icon(Icons.save,
                        color: Color(0xFF000000), size: 16),
                    label: const Text("Save",
                        style: TextStyle(
                            color: Color(0xFF000000),
                            fontWeight: FontWeight.bold)),
                    onPressed: () {
                      setState(() {
                        doc.isUploaded = true;
                        doc.expiryDate =
                            dateCtrl.text.isEmpty ? "Valid" : dateCtrl.text;
                        if (pickedPath != null) {
                          doc.filePath = pickedPath;
                          doc.mimeType = pickedMime;
                        }
                        if (pickedName != null) doc.fileData = pickedName;
                        if (engineCtrl.text.isNotEmpty) {
                          doc.engineNo = engineCtrl.text;
                        }
                        if (chassisCtrl.text.isNotEmpty) {
                          doc.chassisNo = chassisCtrl.text;
                        }
                        if (regCtrl.text.isNotEmpty) doc.regNo = regCtrl.text;
                        if (insurerCtrl.text.isNotEmpty) {
                          doc.insurer = insurerCtrl.text;
                        }
                        if (ownerCtrl.text.isNotEmpty) {
                          doc.ownerName = ownerCtrl.text;
                        }
                        doc.remarks = remarksCtrl.text;
                      });
                      _save();
                      Navigator.pop(c);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                              "âœ… ${doc.name} saved${pickedPath != null ? ' with file' : ''}!")));
                    }),
              ],
            ));
  }

  void _viewFleetDoc(FleetDoc doc) {
    if (doc.filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("No file stored. Re-upload with camera or file picker."),
          behavior: SnackBarBehavior.floating));
      return;
    }
    final file = File(doc.filePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("File not found on device. Please re-upload."),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      return;
    }
    showDialog(
        context: context,
        builder: (c) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text(doc.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15),
                                  overflow: TextOverflow.ellipsis)),
                          IconButton(
                              onPressed: () => Navigator.pop(c),
                              icon: const Icon(Icons.close)),
                        ])),
                const Divider(height: 1),
                if (doc.mimeType.startsWith('image'))
                  Container(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: InteractiveViewer(
                          child: Image.file(file, fit: BoxFit.contain)))
                else
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        const Icon(Icons.picture_as_pdf,
                            size: 60, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(doc.fileData,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF8E1)),
                            onPressed: () async {
                              try {
                                await Share.shareXFiles([XFile(doc.filePath)],
                                    subject: doc.name);
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.share,
                                color: Color(0xFF000000), size: 16),
                            label: const Text("Share / Open",
                                style:
                                    TextStyle(color: Color(0xFF000000)))),
                      ])),
                // Show extracted fields if any
                if (doc.engineNo.isNotEmpty ||
                    doc.chassisNo.isNotEmpty ||
                    doc.regNo.isNotEmpty ||
                    doc.insurer.isNotEmpty)
                  Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Extracted Info",
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF000000),
                                    fontSize: 12)),
                            const SizedBox(height: 6),
                            if (doc.engineNo.isNotEmpty)
                              _infoRow("Engine No", doc.engineNo),
                            if (doc.chassisNo.isNotEmpty)
                              _infoRow("Chassis No (VIN)", doc.chassisNo),
                            if (doc.regNo.isNotEmpty)
                              _infoRow("Reg No", doc.regNo),
                            if (doc.insurer.isNotEmpty)
                              _infoRow("Insurer", doc.insurer),
                            if (doc.remarks.isNotEmpty)
                              _infoRow("Remarks", doc.remarks),
                          ])),
              ]),
            ));
  }

  Widget _infoRow(String label, String val) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 110,
            child: Text("$label:",
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600))),
        Expanded(
            child: Text(val,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF000000)))),
      ]));

  void _viewDriverDoc(DriverDoc doc) {
    if (doc.filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("No file stored. Re-upload with camera or file picker."),
          behavior: SnackBarBehavior.floating));
      return;
    }
    final file = File(doc.filePath);
    showDialog(
        context: context,
        builder: (c) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(doc.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 15)),
                          IconButton(
                              onPressed: () => Navigator.pop(c),
                              icon: const Icon(Icons.close)),
                        ])),
                const Divider(height: 1),
                if (doc.mimeType.startsWith('image') && file.existsSync())
                  Container(
                      constraints: const BoxConstraints(maxHeight: 350),
                      child: InteractiveViewer(
                          child: Image.file(file, fit: BoxFit.contain)))
                else
                  Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        Icon(
                            doc.mimeType == 'application/pdf'
                                ? Icons.picture_as_pdf
                                : Icons.image_not_supported,
                            size: 60,
                            color: Colors.red),
                        const SizedBox(height: 10),
                        Text(doc.fileName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF8E1)),
                            onPressed: () async {
                              try {
                                await Share.shareXFiles([XFile(doc.filePath)],
                                    subject: doc.label);
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.share,
                                color: Color(0xFF000000), size: 16),
                            label: const Text("Share / Open",
                                style:
                                    TextStyle(color: Color(0xFF000000)))),
                      ])),
                if (doc.docNumber.isNotEmpty || doc.expiryDate.isNotEmpty)
                  Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (doc.docNumber.isNotEmpty)
                              _infoRow("ID Number", doc.docNumber),
                            if (doc.expiryDate.isNotEmpty)
                              _infoRow("Expiry", doc.expiryDate),
                            if (doc.uploadDate.isNotEmpty)
                              _infoRow("Uploaded", doc.uploadDate),
                          ])),
              ]),
            ));
  }

  void _addBattery(Asset asset) {
    final makeCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    final billCtrl = TextEditingController();
    final purchCtrl = TextEditingController();
    final warrantExpCtrl = TextEditingController();
    double warrantYears = 1.0;
    showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c2, setSt) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  title: const Text("Add Battery Record",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(
                          child: TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: makeCtrl,
                              decoration: InputDecoration(
                                  labelText: "Make (e.g. Exide)",
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2))))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: modelCtrl,
                              decoration: InputDecoration(
                                  labelText: "Model",
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2)))))
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        controller: serialCtrl,
                        decoration: InputDecoration(
                            labelText: "Serial / Battery No. *",
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00),
                                    width: 2)))),
                    const SizedBox(height: 10),
                    TextField(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        controller: billCtrl,
                        decoration: InputDecoration(
                            labelText: "Bill No.",
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00),
                                    width: 2)))),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: purchCtrl,
                              decoration: InputDecoration(
                                  labelText: "Purchase Date",
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2))))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: warrantExpCtrl,
                              decoration: InputDecoration(
                                  labelText: "Warranty Expiry",
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2)))))
                    ]),
                    const SizedBox(height: 10),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Warranty (Years):",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          Text("${warrantYears.toStringAsFixed(0)} yr",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900))
                        ]),
                    Slider(
                        value: warrantYears,
                        min: 0.5,
                        max: 5,
                        divisions: 9,
                        activeColor: const Color(0xFFFFF8E1),
                        label: "${warrantYears.toStringAsFixed(0)}yr",
                        onChanged: (v) => setSt(() => warrantYears = v)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text("Cancel")),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF8E1)),
                        onPressed: () {
                          if (serialCtrl.text.isEmpty) return;
                          setState(() => asset.batteries.add(Battery(
                              make: makeCtrl.text,
                              model: modelCtrl.text,
                              serialNo: serialCtrl.text,
                              billNo: billCtrl.text,
                              purchaseDate: purchCtrl.text,
                              warrantyExpiry: warrantExpCtrl.text,
                              warrantyYears: warrantYears)));
                          _save();
                          Navigator.pop(c);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                  content: Text("âœ… Battery record added!")));
                        },
                        child: const Text("Save",
                            style: TextStyle(color: Color(0xFF000000))))
                  ],
                )));
  }

  void _sendVehicleDocs(Asset a) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                          color: const PdfColor(0.05, 0.09, 0.16),
                          borderRadius: pw.BorderRadius.circular(8)),
                      child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(userProfile.companyName.toUpperCase(),
                                      style: pw.TextStyle(
                                          fontSize: 16,
                                          fontWeight: pw.FontWeight.bold,
                                          color:
                                              const PdfColor(0.1, 0.23, 0.1))),
                                  pw.Text(userProfile.phone,
                                      style: const pw.TextStyle(
                                          fontSize: 9,
                                          color: PdfColor(0.7, 0.7, 0.8)))
                                ]),
                            pw.Text("VEHICLE DOCUMENT BUNDLE",
                                style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold,
                                    color: const PdfColor(0.1, 0.23, 0.1))),
                          ])),
                  pw.SizedBox(height: 16),
                  pw.Text(a.number,
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text("${a.type} â€¢ ${a.axleCount} Axles â€¢ ${a.payload}",
                      style: const pw.TextStyle(
                          fontSize: 11, color: PdfColor(0.4, 0.4, 0.4))),
                  pw.SizedBox(height: 16),
                  pw.Table(
                      border: pw.TableBorder.all(
                          color: const PdfColor(0.85, 0.85, 0.85), width: 0.8),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(3),
                        1: const pw.FlexColumnWidth(2),
                        2: const pw.FlexColumnWidth(2)
                      },
                      children: [
                        pw.TableRow(
                            decoration: const pw.BoxDecoration(
                                color: PdfColor(0.05, 0.09, 0.16)),
                            children: [
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text("Document",
                                      style: pw.TextStyle(
                                          color: const PdfColor(0.1, 0.23, 0.1),
                                          fontWeight: pw.FontWeight.bold))),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text("Status",
                                      style: pw.TextStyle(
                                          color: const PdfColor(0.1, 0.23, 0.1),
                                          fontWeight: pw.FontWeight.bold))),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text("Expiry",
                                      style: pw.TextStyle(
                                          color: const PdfColor(0.1, 0.23, 0.1),
                                          fontWeight: pw.FontWeight.bold)))
                            ]),
                        ...a.docs.map((d) => pw.TableRow(children: [
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(d.name)),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                      d.isUploaded ? "âœ“ Valid" : "âœ— Missing",
                                      style: pw.TextStyle(
                                          color: d.isUploaded
                                              ? const PdfColor(0, 0.6, 0)
                                              : const PdfColor(0.8, 0, 0)))),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                      d.isUploaded ? d.expiryDate : "-"))
                            ])),
                      ]),
                  if (a.batteries.isNotEmpty) ...[
                    pw.SizedBox(height: 12),
                    pw.Text("Battery Records",
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 6),
                    pw.Table(
                        border: pw.TableBorder.all(
                            color: const PdfColor(0.85, 0.85, 0.85),
                            width: 0.8),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(2),
                          1: const pw.FlexColumnWidth(2),
                          2: const pw.FlexColumnWidth(1.5),
                          3: const pw.FlexColumnWidth(1.5)
                        },
                        children: [
                          pw.TableRow(
                              decoration: const pw.BoxDecoration(
                                  color: PdfColor(0.9, 0.9, 0.9)),
                              children: [
                                "Make/Model",
                                "Serial No.",
                                "Bill No.",
                                "Warranty"
                              ]
                                  .map((h) => pw.Padding(
                                      padding: const pw.EdgeInsets.all(6),
                                      child: pw.Text(h,
                                          style: pw.TextStyle(
                                              fontWeight: pw.FontWeight.bold,
                                              fontSize: 9))))
                                  .toList()),
                          ...a.batteries.map((b) => pw.TableRow(children: [
                                pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text("${b.make} ${b.model}",
                                        style:
                                            const pw.TextStyle(fontSize: 9))),
                                pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(b.serialNo,
                                        style:
                                            const pw.TextStyle(fontSize: 9))),
                                pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                        b.billNo.isNotEmpty ? b.billNo : 'N/A',
                                        style:
                                            const pw.TextStyle(fontSize: 9))),
                                pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                        "${b.warrantyYears}yr till ${b.warrantyExpiry}",
                                        style: const pw.TextStyle(fontSize: 9)))
                              ])),
                        ]),
                  ],
                ])));
    try {
      await Printing.sharePdf(
          bytes: await pdf.save(), filename: 'VehicleDocs_${a.number}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // Indian commercial vehicle: tyre count â†’ axles
  // Front axle: 2 tyres (single). Rear axles: 4 tyres each (dual).
  // 6T=3ax, 10T=5ax, 12T=6ax (standard tanker), 14T=7ax, 16T=8ax, 18T=10ax, 22T=12ax
  int _tyresToAxles(int tyres) {
    if (tyres <= 4) return 2;
    if (tyres == 6) return 3;
    if (tyres == 8) return 4;
    if (tyres == 10) return 5;
    if (tyres == 12) return 6;
    if (tyres == 14) return 7;
    if (tyres == 16) return 8;
    if (tyres == 18) return 9;
    if (tyres == 20) return 10;
    if (tyres == 22) return 11;
    if (tyres == 24) return 12;
    // General formula: front axle has 2 tyres, each additional axle adds 4
    return ((tyres - 2) ~/ 4) + 1;
  }

  // Default tyres by vehicle type
  int _defaultTyres(String type) {
    switch (type) {
      case 'LCV':
        return 6;
      case 'SS Tanker':
      case 'MS Tanker':
        return 12; // 6-axle standard
      case 'Container':
      case 'Open Truck':
        return 10;
      case 'Trailer':
        return 18;
      case 'Reefer':
        return 10;
      default:
        return 12;
    }
  }

  void _addVehicle() {
    final numCtrl = TextEditingController();
    final tyCtrl = TextEditingController(text: "12");
    final axCtrl = TextEditingController(text: "6");
    final payCtrl = TextEditingController(text: "30 Ton");
    String vType = "SS Tanker";

    showDialog(
        context: context,
        builder: (c) => StatefulBuilder(builder: (c2, setSt) {
              void onTyreChange() {
                final t = int.tryParse(tyCtrl.text) ?? 0;
                if (t > 0) {
                  axCtrl.text = _tyresToAxles(t).toString();
                  setSt(() {});
                }
              }

              tyCtrl.addListener(onTyreChange);

              final axles = int.tryParse(axCtrl.text) ?? 6;
              final tollRate = kTollPerAxlePerKm[axles] ?? 2.40;

              return AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Row(children: [
                  Icon(Icons.local_shipping, color: Color(0xFF000000)),
                  SizedBox(width: 8),
                  Text("Add New Vehicle",
                      style: TextStyle(fontWeight: FontWeight.w800))
                ]),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      TextField(
                          style: const TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                          controller: numCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                              labelText: "Vehicle Number *",
                              hintText: "GJ-01-WT-1234",
                              prefixIcon: const Icon(Icons.confirmation_number,
                                  size: 18),
                              filled: true,
                              fillColor: const Color(0xFFFFF8E1),
                              labelStyle: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                              floatingLabelStyle: const TextStyle(
                                  color: Color(0xFFFB8C00),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00),
                                      width: 2)))),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          style: const TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                          initialValue: vType,
                          decoration: InputDecoration(
                              labelText: "Vehicle Type",
                              prefixIcon: const Icon(Icons.category, size: 18),
                              filled: true,
                              fillColor: const Color(0xFFFFF8E1),
                              labelStyle: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                              floatingLabelStyle: const TextStyle(
                                  color: Color(0xFFFB8C00),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00),
                                      width: 2))),
                          items: [
                            "SS Tanker",
                            "MS Tanker",
                            "Container",
                            "Open Truck",
                            "Trailer",
                            "LCV",
                            "Reefer"
                          ]
                              .map((v) =>
                                  DropdownMenuItem(value: v, child: Text(v)))
                              .toList(),
                          onChanged: (v) {
                            setSt(() {
                              vType = v!;
                              tyCtrl.text = _defaultTyres(v).toString();
                              axCtrl.text =
                                  _tyresToAxles(_defaultTyres(v)).toString();
                            });
                          }),
                      const SizedBox(height: 12),
                      TextField(
                          style: const TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                          controller: payCtrl,
                          decoration: InputDecoration(
                              labelText: "Payload Capacity",
                              hintText: "e.g. 30 Ton",
                              prefixIcon: const Icon(Icons.scale, size: 18),
                              filled: true,
                              fillColor: const Color(0xFFFFF8E1),
                              labelStyle: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                              floatingLabelStyle: const TextStyle(
                                  color: Color(0xFFFB8C00),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFFB8C00),
                                      width: 2)))),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                controller: tyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                    labelText: "No. of Tyres",
                                    hintText: "12",
                                    prefixIcon:
                                        const Icon(Icons.circle, size: 16),
                                    filled: true,
                                    fillColor: const Color(0xFFFFF8E1),
                                    labelStyle: const TextStyle(
                                        color: Color(0xFF000000),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                    floatingLabelStyle: const TextStyle(
                                        color: Color(0xFFFB8C00),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFB8C00))),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFB8C00))),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFB8C00),
                                            width: 2))))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: TextField(
                                controller: axCtrl,
                                keyboardType: TextInputType.number,
                                readOnly: true,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF000000)),
                                decoration: InputDecoration(
                                    labelText: "Axles (auto)",
                                    prefixIcon: const Icon(Icons.linear_scale,
                                        size: 16),
                                    filled: true,
                                    fillColor: const Color(0xFFFFF8E1),
                                    labelStyle: const TextStyle(
                                        color: Color(0xFF000000),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                    floatingLabelStyle: const TextStyle(
                                        color: Color(0xFFFB8C00),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFB8C00))),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFB8C00))),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFB8C00),
                                            width: 2))))),
                      ]),
                      const SizedBox(height: 8),
                      // FASTag rate preview
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            const Icon(Icons.toll,
                                color: Colors.orange, size: 16),
                            const SizedBox(width: 8),
                            Text(
                                "FASTag: â‚¹${tollRate.toStringAsFixed(2)}/km (NHAI FY2024-25, $axles-axle)",
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w700)),
                          ])),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancel")),
                  ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF8E1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.save,
                          color: Color(0xFF000000), size: 16),
                      label: const Text("Add Vehicle",
                          style: TextStyle(
                              color: Color(0xFF000000),
                              fontWeight: FontWeight.bold)),
                      onPressed: () {
                        if (numCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Enter vehicle number"),
                                  backgroundColor: Colors.red));
                          return;
                        }
                        final tc = int.tryParse(tyCtrl.text) ?? 12;
                        final ac = int.tryParse(axCtrl.text) ?? 6;
                        setState(() => fleet.add(Asset(
                            id: "V${DateTime.now().millisecondsSinceEpoch}",
                            number: numCtrl.text.toUpperCase(),
                            type: vType,
                            payload:
                                payCtrl.text.isEmpty ? "30 Ton" : payCtrl.text,
                            tyreCount: tc,
                            axleCount: ac,
                            tyreSerials: List.filled(tc, ""),
                            batteries: [],
                            docs: VehicleDocConfig.getRequiredDocs(vType)
                                .map((d) => FleetDoc(name: d))
                                .toList())));
                        _save();
                        Navigator.pop(c);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                                "âœ… ${numCtrl.text.toUpperCase()} added â€” $ac axles, $tc tyres")));
                      }),
                ],
              );
            }));
  }

  void _editAsset(Asset asset) {
    final cs = List.generate(asset.tyreCount,
        (i) => TextEditingController(text: asset.tyreSerials[i]));
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text("Tyre Serials â€” ${asset.number}",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                        child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 2.5,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10),
                            itemCount: asset.tyreCount,
                            itemBuilder: (_, i) => TextField(
                                controller: cs[i],
                                decoration: InputDecoration(
                                    labelText: "T${i + 1}",
                                    border: const OutlineInputBorder(),
                                    contentPadding:
                                        const EdgeInsets.all(8)))))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Cancel")),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo),
                      onPressed: () {
                        setState(() {
                          for (int i = 0; i < asset.tyreCount; i++) {
                            asset.tyreSerials[i] = cs[i].text;
                          }
                        });
                        _save();
                        Navigator.pop(ctx);
                      },
                      child: const Text("Save",
                          style: TextStyle(color: Color(0xFF000000))))
                ]));
  }

  // â”€â”€ DRIVERS TAB â”€â”€
  Widget _buildDrivers() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Driver Roster",
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF000000))),
          ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF8E1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: _addDriver,
              icon: const Icon(Icons.person_add,
                  color: Color(0xFF000000), size: 16),
              label: const Text("Add Driver",
                  style:
                      TextStyle(color: Color(0xFF000000), fontSize: 12)))
        ]),
        const SizedBox(height: 20),
        if (drivers.isEmpty)
          const Center(
              child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Column(children: [
                    Icon(Icons.group_off, size: 60, color: Colors.grey),
                    SizedBox(height: 12),
                    Text("No drivers added",
                        style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 16))
                  ]))),
        ...drivers.map((d) => Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: const Color(0xFF000000),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 12)
                ]),
            child: ExpansionTile(
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                  radius: 26,
                  backgroundColor:
                      d.isVerified ? Colors.green[50] : Colors.blue[50],
                  child: Stack(children: [
                    Text(d.name.isNotEmpty ? d.name[0].toUpperCase() : "D",
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: Color(0xFF000000))),
                    if (d.isVerified)
                      const Positioned(
                          bottom: 0,
                          right: 0,
                          child: Icon(Icons.verified,
                              size: 14, color: Colors.green))
                  ])),
              title: Text(d.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.phone,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                            fontSize: 13)),
                    Row(children: [
                      if (d.aadharNum.isNotEmpty)
                        Container(
                            margin: const EdgeInsets.only(right: 6, top: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text("Aadhaar âœ“",
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.blue[800],
                                    fontWeight: FontWeight.bold))),
                      if (d.dlNum.isNotEmpty)
                        Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text("DL âœ“",
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.bold))),
                    ]),
                  ]),
              trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text("Balance",
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                        FittedBox(
                            child: Text("â‚¹${d.balance.toStringAsFixed(0)}",
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: d.balance >= 0
                                        ? Colors.green
                                        : Colors.red)))
                      ])),
              children: [
                Container(
                    padding: const EdgeInsets.all(16),
                    color: const Color(0xFF000000),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("KYC Documents",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: Color(0xFF000000))),
                          const SizedBox(height: 10),
                          ...d.documents.map((doc) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                      color: doc.isUploaded
                                          ? Colors.green[50]
                                          : Colors.orange[50],
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: doc.isUploaded
                                              ? Colors.green[200]!
                                              : Colors.orange[200]!)),
                                  child: Row(children: [
                                    Icon(
                                        doc.isUploaded
                                            ? Icons.check_circle
                                            : Icons.warning_amber,
                                        color: doc.isUploaded
                                            ? Colors.green
                                            : Colors.orange,
                                        size: 16),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(doc.label,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                          if (doc.docNumber.isNotEmpty)
                                            Text("No: ${doc.docNumber}",
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 11)),
                                          if (doc.isUploaded)
                                            Text("Uploaded: ${doc.uploadDate}",
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 10)),
                                        ])),
                                    Row(children: [
                                      if (doc.isUploaded &&
                                          doc.filePath.isNotEmpty)
                                        IconButton(
                                            icon: const Icon(Icons.visibility,
                                                size: 18, color: Colors.teal),
                                            tooltip: "View",
                                            onPressed: () =>
                                                _viewDriverDoc(doc)),
                                      IconButton(
                                          icon: const Icon(Icons.camera_alt,
                                              size: 18, color: Colors.blue),
                                          onPressed: () => _uploadDriverDoc(
                                              d, doc, DocUploadMethod.camera)),
                                      IconButton(
                                          icon: const Icon(Icons.upload_file,
                                              size: 18, color: Colors.indigo),
                                          onPressed: () => _uploadDriverDoc(
                                              d, doc, DocUploadMethod.file)),
                                    ]),
                                  ])))),
                          if (d.monthlySalary > 0)
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.purple.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(
                                    "Monthly Salary: â‚¹${d.monthlySalary.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                        color: Colors.purple,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12))),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                                child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFFFF8E1),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10))),
                                    onPressed: () async {
                                      await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  DriverLedgerScreen(
                                                      driver: d,
                                                      onUpdate: () =>
                                                          _save())));
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.receipt_long,
                                        size: 15,
                                        color: Color(0xFF000000)),
                                    label: const Text("Driver Ledger",
                                        style: TextStyle(
                                            color: Color(0xFF000000),
                                            fontSize: 12)))),
                          ]),
                        ]))
              ],
            ))),
      ]);

  Future<void> _uploadDriverDoc(
      Driver driver, DriverDoc doc, DocUploadMethod method) async {
    String? pickedFile;
    String? pickedPath;
    String pickedMime = 'image/jpeg';
    Map<String, String> ocrData = {};
    try {
      if (method == DocUploadMethod.camera) {
        final xfile = await ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 95,
            maxWidth: 2048,
            maxHeight: 2048,
            preferredCameraDevice: CameraDevice.rear);
        if (xfile != null) {
          pickedFile = xfile.name;
          pickedPath = xfile.path;
          pickedMime = 'image/jpeg';
        }
      } else {
        final res = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
            allowMultiple: false,
            withData: false);
        if (res != null && res.files.isNotEmpty) {
          pickedFile = res.files.single.name;
          pickedPath = res.files.single.path;
          pickedMime = pickedFile.endsWith('.pdf') == true
              ? 'application/pdf'
              : 'image/jpeg';
        }
      }
    } catch (e) {
      pickedFile = null;
    }

    // Run OCR on the image
    if (pickedPath != null && pickedMime.startsWith('image') && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF000000))),
            SizedBox(width: 12),
            Text("Reading document details...")
          ]),
          backgroundColor: Colors.indigo,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 6)));
      ocrData = await FirebaseService.extractDocumentText(pickedPath);
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    if (!mounted) return;
    // Pre-fill from OCR
    String ocrDocNum = '';
    if (doc.type == 'aadhaar' && ocrData['aadhaarNo'] != null) {
      ocrDocNum = ocrData['aadhaarNo']!;
    }
    if (doc.type == 'dl' && ocrData['dlNo'] != null) {
      ocrDocNum = ocrData['dlNo']!;
    }
    final numCtrl = TextEditingController(
        text: ocrDocNum.isNotEmpty ? ocrDocNum : doc.docNumber);
    final expCtrl = TextEditingController(text: ocrData['expiryDate'] ?? '');
    showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, ss) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  title: Row(children: [
                    Icon(
                        pickedFile != null
                            ? Icons.check_circle
                            : Icons.edit_document,
                        color: pickedFile != null
                            ? Colors.green
                            : const Color(0xFFFFF8E1),
                        size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text("Upload ${doc.label}",
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800))),
                  ]),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pickedFile != null)
                          Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.green.shade200)),
                              child: Row(children: [
                                const Icon(Icons.attach_file,
                                    color: Colors.green, size: 18),
                                const SizedBox(width: 8),
                                Flexible(
                                    child: Text(pickedFile,
                                        style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis)),
                              ]))
                        else
                          Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Text(
                                  "Enter details manually or try again",
                                  style: TextStyle(
                                      color: Colors.orange, fontSize: 12))),
                        TextField(
                            style: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                            controller: numCtrl,
                            decoration: InputDecoration(
                                labelText: doc.type == 'aadhaar'
                                    ? "Aadhaar Number (12 digits)"
                                    : doc.type == 'dl'
                                        ? "DL Number"
                                        : "Reference Number",
                                prefixIcon: Icon(
                                    doc.type == 'aadhaar'
                                        ? Icons.fingerprint
                                        : doc.type == 'dl'
                                            ? Icons.card_membership
                                            : Icons.numbers,
                                    size: 18),
                                filled: true,
                                fillColor: const Color(0xFFFFF8E1),
                                labelStyle: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                                floatingLabelStyle: const TextStyle(
                                    color: Color(0xFFFB8C00),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00))),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFFB8C00),
                                        width: 2)))),
                        if (doc.type != 'photo') ...[
                          const SizedBox(height: 10),
                          TextField(
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              controller: expCtrl,
                              decoration: InputDecoration(
                                  labelText: "Expiry Date (DD/MM/YYYY)",
                                  hintText: "e.g. 31/12/2028",
                                  prefixIcon: const Icon(Icons.calendar_today,
                                      size: 18),
                                  filled: true,
                                  fillColor: const Color(0xFFFFF8E1),
                                  labelStyle: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  floatingLabelStyle: const TextStyle(
                                      color: Color(0xFFFB8C00),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFB8C00),
                                          width: 2)))),
                        ],
                      ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text("Cancel")),
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF8E1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        icon: const Icon(Icons.check,
                            color: Color(0xFF000000), size: 16),
                        label: const Text("Save",
                            style: TextStyle(
                                color: Color(0xFF000000),
                                fontWeight: FontWeight.bold)),
                        onPressed: () {
                          setState(() {
                            doc.isUploaded = true;
                            doc.docNumber = numCtrl.text;
                            doc.uploadDate =
                                "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
                            if (expCtrl.text.isNotEmpty) {
                              doc.expiryDate = expCtrl.text;
                            }
                            if (pickedFile != null) {
                              doc.fileName = pickedFile;
                            }
                            if (pickedPath != null) {
                              doc.filePath = pickedPath;
                              doc.mimeType = pickedMime;
                            }
                            if (doc.type == 'aadhaar' &&
                                numCtrl.text.isNotEmpty) {
                              driver.aadharNum = numCtrl.text;
                            }
                            if (doc.type == 'dl' && numCtrl.text.isNotEmpty) {
                              driver.dlNum = numCtrl.text;
                            }
                          });
                          _save();
                          Navigator.pop(c);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                  "âœ… ${doc.label} ${pickedFile != null ? 'uploaded' : 'recorded'}!")));
                        }),
                  ],
                )));
  }

  void _addDriver() {
    final nm = TextEditingController();
    final ph = TextEditingController();
    final aa = TextEditingController();
    final dl = TextEditingController();
    final sl = TextEditingController();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (c) => Container(
              decoration: const BoxDecoration(
                  color: Color(0xFFFBF7F0),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28))),
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(c).viewInsets.bottom,
                  left: 24,
                  right: 24,
                  top: 28),
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Add New Driver",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF000000))),
                const SizedBox(height: 18),
                Center(
                    child: Stack(children: [
                  CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.blue.withOpacity(0.18),
                      child: const Icon(Icons.person,
                          size: 40, color: Colors.blue)),
                  Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                          onTap: () async {
                            try {
                              final img = await ImagePicker().pickImage(
                                  source: ImageSource.camera, imageQuality: 90);
                              if (img != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        backgroundColor: Colors.green,
                                        behavior: SnackBarBehavior.floating,
                                        content: Text(
                                            "ðŸ“¸ Photo captured: ${img.name}")));
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Camera unavailable â€” check permissions"),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating));
                            }
                          },
                          child: CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(0xFFFFF8E1),
                              child: const Icon(Icons.camera_alt,
                                  size: 16, color: Color(0xFF000000))))),
                ])),
                const SizedBox(height: 18),
                TextField(
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    controller: nm,
                    decoration: InputDecoration(
                        labelText: "Full Name *",
                        prefixIcon: const Icon(Icons.person),
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2)))),
                const SizedBox(height: 12),
                TextField(
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    controller: ph,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                        labelText: "Phone Number *",
                        prefixIcon: const Icon(Icons.phone),
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2)))),
                const SizedBox(height: 12),
                TextField(
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    controller: sl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: "Monthly Salary (â‚¹)",
                        prefixIcon: const Icon(Icons.currency_rupee),
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2)))),
                const SizedBox(height: 12),
                TextField(
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    controller: aa,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    decoration: InputDecoration(
                        counterText: "",
                        labelText: "Aadhaar Number (12 digits)",
                        prefixIcon: const Icon(Icons.credit_card),
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2)))),
                const SizedBox(height: 12),
                TextField(
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    controller: dl,
                    decoration: InputDecoration(
                        labelText: "Driving Licence Number",
                        prefixIcon: const Icon(Icons.directions_car),
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2)))),
                const SizedBox(height: 12),
                // Aadhaar + DL quick upload row
                StatefulBuilder(builder: (ctx, setDoc) {
                  bool aadhaarDone = aa.text.isNotEmpty;
                  bool dlDone = dl.text.isNotEmpty;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Quick Document Scan",
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF000000))),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: GestureDetector(
                                  onTap: () async {
                                    try {
                                      final img = await ImagePicker().pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 90);
                                      if (img != null) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                backgroundColor: Colors.indigo,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                content: Text(
                                                    "Reading Aadhaar...")));
                                        final ocr = await FirebaseService
                                            .extractDocumentText(img.path);
                                        ScaffoldMessenger.of(context)
                                            .hideCurrentSnackBar();
                                        if (ocr['aadhaarNo'] != null) {
                                          aa.text = ocr['aadhaarNo']!;
                                          setDoc(() {});
                                        }
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                backgroundColor: Colors.green,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                content: Text(ocr[
                                                            'aadhaarNo'] !=
                                                        null
                                                    ? "Aadhaar: ${ocr['aadhaarNo']}"
                                                    : "Photo captured â€” enter number manually")));
                                      }
                                    } catch (_) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content:
                                                  Text("Camera unavailable"),
                                              backgroundColor: Colors.red));
                                    }
                                  },
                                  child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: aadhaarDone
                                              ? Colors.green[50]
                                              : const Color(0xFFFFF8E1)
                                                  .withOpacity(0.05),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: aadhaarDone
                                                  ? Colors.green
                                                  : const Color(0xFFFFF8E1))),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                                aadhaarDone
                                                    ? Icons.check_circle
                                                    : Icons.camera_alt,
                                                size: 16,
                                                color: aadhaarDone
                                                    ? Colors.green
                                                    : const Color(0xFFFFF8E1)),
                                            const SizedBox(width: 6),
                                            Text("Scan Aadhaar",
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: aadhaarDone
                                                        ? Colors.green
                                                        : const Color(
                                                            0xFF0D1F14)))
                                          ])))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: GestureDetector(
                                  onTap: () async {
                                    try {
                                      final img = await ImagePicker().pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 90);
                                      if (img != null) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                backgroundColor: Colors.indigo,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                content: Text(
                                                    "Reading Driving Licence...")));
                                        final ocr = await FirebaseService
                                            .extractDocumentText(img.path);
                                        ScaffoldMessenger.of(context)
                                            .hideCurrentSnackBar();
                                        if (ocr['dlNo'] != null) {
                                          dl.text = ocr['dlNo']!;
                                          setDoc(() {});
                                        }
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                backgroundColor: Colors.green,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                content: Text(ocr['dlNo'] !=
                                                        null
                                                    ? "DL: ${ocr['dlNo']}"
                                                    : "Photo captured â€” enter number manually")));
                                      }
                                    } catch (_) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content:
                                                  Text("Camera unavailable"),
                                              backgroundColor: Colors.red));
                                    }
                                  },
                                  child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: dlDone
                                              ? Colors.green[50]
                                              : Colors.blue.withOpacity(0.05),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: dlDone
                                                  ? Colors.green
                                                  : Colors.blue)),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                                dlDone
                                                    ? Icons.check_circle
                                                    : Icons.camera_alt,
                                                size: 16,
                                                color: dlDone
                                                    ? Colors.green
                                                    : Colors.blue),
                                            const SizedBox(width: 6),
                                            Text("Scan DL",
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: dlDone
                                                        ? Colors.green
                                                        : Colors.blue))
                                          ])))),
                        ]),
                      ]);
                }),
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF8E1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        onPressed: () {
                          final d = Driver(
                              id: "D${drivers.length + 1}",
                              name: nm.text,
                              phone: ph.text,
                              balance: 0,
                              transactions: [],
                              aadharNum: aa.text,
                              dlNum: dl.text,
                              monthlySalary: double.tryParse(sl.text) ?? 0);
                          if (aa.text.isNotEmpty) {
                            final doc = d.documents
                                .firstWhere((doc) => doc.type == 'aadhaar');
                            doc.docNumber = aa.text;
                            doc.isUploaded = true;
                            doc.uploadDate =
                                "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
                          }
                          if (dl.text.isNotEmpty) {
                            final doc = d.documents
                                .firstWhere((doc) => doc.type == 'dl');
                            doc.docNumber = dl.text;
                            doc.isUploaded = true;
                            doc.uploadDate =
                                "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
                          }
                          setState(() => drivers.add(d));
                          _save();
                          Navigator.pop(c);
                        },
                        child: const Text("Save Driver",
                            style: TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 16,
                                fontWeight: FontWeight.bold)))),
                const SizedBox(height: 24),
              ])),
            ));
  }

  // â”€â”€ PROFILE â”€â”€
  void _openProfile() {
    final cn = TextEditingController(text: userProfile.companyName);
    final cg = TextEditingController(text: userProfile.gstin);
    final cp = TextEditingController(text: userProfile.phone);
    final ca = TextEditingController(text: userProfile.address);
    final ce = TextEditingController(text: userProfile.email);
    final cb = TextEditingController(text: userProfile.bankName);
    final cac = TextEditingController(text: userProfile.bankAccount);
    final ci = TextEditingController(text: userProfile.bankIfsc);
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                  appBar: AppBar(
                      backgroundColor: const Color(0xFFFFF8E1),
                      iconTheme:
                          const IconThemeData(color: Color(0xFF000000)),
                      title: const Text("Company Profile",
                          style: TextStyle(
                              color: Color(0xFF000000),
                              fontWeight: FontWeight.w900))),
                  body: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                                onTap: _openSub,
                                child: Container(
                                    padding: const EdgeInsets.all(18),
                                    margin: const EdgeInsets.only(bottom: 24),
                                    decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                            colors: [
                                              const Color(0xFFFFF8E1),
                                              subscription.tierColor
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight),
                                        borderRadius:
                                            BorderRadius.circular(18)),
                                    child: Row(children: [
                                      Icon(Icons.workspace_premium,
                                          color: subscription.tierColor,
                                          size: 30),
                                      const SizedBox(width: 14),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(
                                                "${subscription.tierName} Plan",
                                                style: const TextStyle(
                                                    color:
                                                        Color(0xFF000000),
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 18)),
                                            Text(
                                                subscription.tier ==
                                                        SubscriptionTier.free
                                                    ? "10 trips/month"
                                                    : subscription.tier ==
                                                            SubscriptionTier
                                                                .enterprise
                                                        ? "50+ vehicles â€¢ 10 users"
                                                        : "Unlimited â€¢ PDF + GPS",
                                                style: const TextStyle(
                                                    color: Color(0x701C1917),
                                                    fontSize: 12),
                                                overflow: TextOverflow.ellipsis)
                                          ])),
                                      const Text("Upgrade â†’",
                                          style: TextStyle(
                                              color: Color(0x701C1917),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12))
                                    ]))),
                            const Text("Company Details",
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF000000))),
                            const SizedBox(height: 14),
                            TextField(
                                style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                controller: cn,
                                decoration: InputDecoration(
                                    labelText: "Company Name",
                                    prefixIcon: Icon(Icons.business),
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 12),
                            TextField(
                                style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                controller: cg,
                                decoration: InputDecoration(
                                    labelText: "GSTIN",
                                    prefixIcon: Icon(Icons.receipt),
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 12),
                            TextField(
                                style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                controller: cp,
                                decoration: InputDecoration(
                                    labelText: "Phone",
                                    prefixIcon: Icon(Icons.phone),
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 12),
                            TextField(
                                style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                controller: ce,
                                decoration: InputDecoration(
                                    labelText: "Email",
                                    prefixIcon: Icon(Icons.email),
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 12),
                            TextField(
                                style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                controller: ca,
                                maxLines: 2,
                                decoration: InputDecoration(
                                    labelText: "Address",
                                    prefixIcon: Icon(Icons.location_on),
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 18),
                            const Text("Bank Details",
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF000000))),
                            const SizedBox(height: 12),
                            TextField(
                                style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                controller: cb,
                                decoration: InputDecoration(
                                    labelText: "Bank Name",
                                    prefixIcon: Icon(Icons.account_balance),
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                  child: TextField(
                                      style: const TextStyle(
                                          color: Color(0xFF000000),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                      controller: cac,
                                      decoration: InputDecoration(
                                          labelText: "Account No.",
                                          border: OutlineInputBorder()))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: TextField(
                                      style: const TextStyle(
                                          color: Color(0xFF000000),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                      controller: ci,
                                      decoration: InputDecoration(
                                          labelText: "IFSC Code",
                                          border: OutlineInputBorder())))
                            ]),
                            const SizedBox(height: 22),
                            SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12))),
                                    onPressed: () {
                                      setState(() {
                                        userProfile.companyName = cn.text;
                                        userProfile.gstin = cg.text;
                                        userProfile.phone = cp.text;
                                        userProfile.address = ca.text;
                                        userProfile.email = ce.text;
                                        userProfile.bankName = cb.text;
                                        userProfile.bankAccount = cac.text;
                                        userProfile.bankIfsc = ci.text;
                                      });
                                      _save();
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text("Profile Updated"),
                                              backgroundColor: Colors.green));
                                    },
                                    child: const Text("Save Details",
                                        style: TextStyle(
                                            color: Color(0xFFFFF8E1),
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)))),
                            const SizedBox(height: 20),
                            // Logout button
                            GestureDetector(
                              onTap: () => showDialog(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                        backgroundColor:
                                            const Color(0xFFFFF8E1),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                        title: const Row(children: [
                                          Icon(Icons.logout_rounded,
                                              color: Color(0xFFE53E3E)),
                                          SizedBox(width: 10),
                                          Text("Sign Out",
                                              style: TextStyle(
                                                  color:
                                                      Color(0xFF000000),
                                                  fontWeight: FontWeight.w900))
                                        ]),
                                        content: const Text(
                                            "You will be signed out and need to login again.",
                                            style: TextStyle(
                                                color:
                                                    Color(0xFF000000))),
                                        actions: [
                                          TextButton(
                                              onPressed: () => Navigator.pop(c),
                                              child: const Text("Cancel",
                                                  style: TextStyle(
                                                      color: Color(
                                                          0xFF8FBC8F)))),
                                          GestureDetector(
                                            onTap: () async {
                                              final prefs =
                                                  await SharedPreferences
                                                      .getInstance();
                                              await prefs.setBool(
                                                  'rm_session_active', false);
                                              try {
                                                await FirebaseService.auth
                                                    .signOut();
                                              } catch (_) {}
                                              if (!mounted) return;
                                              Navigator.of(context)
                                                  .pushAndRemoveUntil(
                                                      MaterialPageRoute(
                                                          builder: (_) =>
                                                              const LoginScreen()),
                                                      (_) => false);
                                            },
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 18,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFE53E3E),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10)),
                                                child: const Text("Sign Out",
                                                    style: TextStyle(
                                                        color: Color(
                                                            0xFFF2EDE4),
                                                        fontWeight:
                                                            FontWeight.w800))),
                                          ),
                                        ],
                                      )),
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 8),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFE53E3E)
                                        .withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: const Color(0xFFE53E3E)
                                            .withOpacity(0.3))),
                                child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.logout_rounded,
                                          color: Color(0xFFE53E3E),
                                          size: 18),
                                      SizedBox(width: 8),
                                      Text("Sign Out",
                                          style: TextStyle(
                                              color: Color(0xFFE53E3E),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15))
                                    ]),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                                child: Text(
                                    "Route Master ERP v${AppConfig.appVersion}",
                                    style: const TextStyle(
                                        color: Color(0xFFE2E8F0),
                                        fontSize: 10))),
                          ])),
                )));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(
              child:
                  CircularProgressIndicator(color: Color(0xFF000000))));
    }
    return Scaffold(
        appBar: AppBar(
            elevation: 0,
            flexibleSpace: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFFFFF8E1), Color(0xFFFB8C00)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight))),
            backgroundColor: Colors.transparent,
            title: GestureDetector(
                onTap: () {},
                onLongPress: _promptAdminPin,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFB8C00),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.local_shipping_rounded,
                          color: Color(0xFF000000), size: 16)),
                  const SizedBox(width: 8),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("ROUTE MASTER",
                            style: TextStyle(
                                color: Color(0xFF000000),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                fontSize: 14,
                                height: 1.1)),
                        Text("ERP  v${AppConfig.appVersion}",
                            style: const TextStyle(
                                color: Color(0xFF93C5FD),
                                fontWeight: FontWeight.w600,
                                fontSize: 9,
                                letterSpacing: 2)),
                      ]),
                ])),
            actions: [
              IconButton(
                  icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: const Color(0xFF000000).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.person_outline_rounded,
                          color: Color(0xFF000000), size: 20)),
                  onPressed: _openProfile),
              const SizedBox(width: 4),
            ]),
        body: IndexedStack(index: _idx, children: [
          _buildDash(),
          _buildFindLoad(),
          _buildPostLoad(),
          _buildKhata(),
          _buildFleet(),
          _buildDrivers()
        ]),
        bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              border: const Border(
                  top: BorderSide(color: Color(0xFFFB8C00), width: 1)),
            ),
            child: SafeArea(
              child: BottomNavigationBar(
                  currentIndex: _idx,
                  type: BottomNavigationBarType.fixed,
                  selectedItemColor: const Color(0xFFFB8C00),
                  unselectedItemColor: const Color(0xFF000000),
                  backgroundColor: Colors.transparent,
                  selectedFontSize: 9,
                  unselectedFontSize: 9,
                  elevation: 0,
                  onTap: (i) => setState(() => _idx = i),
                  items: const [
                    BottomNavigationBarItem(
                        icon: Icon(Icons.dashboard_outlined, size: 22),
                        activeIcon: Icon(Icons.dashboard_rounded, size: 22),
                        label: "Home"),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.search_outlined, size: 22),
                        activeIcon: Icon(Icons.search_rounded, size: 22),
                        label: "Find Load"),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.add_box_outlined, size: 22),
                        activeIcon: Icon(Icons.add_box_rounded, size: 22),
                        label: "Dispatch"),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.receipt_long_outlined, size: 22),
                        activeIcon: Icon(Icons.receipt_long_rounded, size: 22),
                        label: "Khata"),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.local_shipping_outlined, size: 22),
                        activeIcon:
                            Icon(Icons.local_shipping_rounded, size: 22),
                        label: "Fleet"),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.badge_outlined, size: 22),
                        activeIcon: Icon(Icons.badge_rounded, size: 22),
                        label: "Drivers"),
                  ]),
            ))); // closes SafeArea
  }
}

// ================================================================
// CITY SEARCH FIELD
// ================================================================
// ================================================================
// FACTORY SEARCH FIELD â€” Google Places autocomplete for factories/plants
// ================================================================
class FactorySearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String label;
  final Color iconColor;
  final Function(String name, String placeId) onSelected;
  const FactorySearchField(
      {super.key,
      this.controller,
      required this.label,
      required this.iconColor,
      required this.onSelected});
  @override
  State<FactorySearchField> createState() => _FactorySearchFieldState();
}

class _FactorySearchFieldState extends State<FactorySearchField> {
  late TextEditingController _ctrl;
  List<Map<String, String>> _sugg = [];
  final bool _show = false;
  bool _selecting = false;
  Timer? _deb;

  // Well-known industrial facilities in India
  static const List<Map<String, String>> kKnownFactories = [
    {
      'name': 'Reliance Industries Ltd - Jamnagar Refinery',
      'location': 'Jamnagar, Gujarat'
    },
    {
      'name': 'Reliance Industries Ltd - Hazira Complex',
      'location': 'Hazira, Surat, Gujarat'
    },
    {'name': 'IOCL Koyali Refinery', 'location': 'Vadodara, Gujarat'},
    {'name': 'IOCL Mathura Refinery', 'location': 'Mathura, Uttar Pradesh'},
    {'name': 'IOCL Panipat Refinery', 'location': 'Panipat, Haryana'},
    {'name': 'BPCL Mahul Terminal', 'location': 'Mumbai, Maharashtra'},
    {
      'name': 'HPCL Vishakh Refinery',
      'location': 'Visakhapatnam, Andhra Pradesh'
    },
    {'name': 'Nayara Energy Vadinar', 'location': 'Jamnagar, Gujarat'},
    {'name': 'ONGC Hazira Plant', 'location': 'Hazira, Gujarat'},
    {'name': 'Deepak Nitrite Ltd', 'location': 'Dahej, Gujarat'},
    {
      'name': 'Deepak Fertilisers Taloja',
      'location': 'Navi Mumbai, Maharashtra'
    },
    {'name': 'Gujarat Fluorochemicals Ltd', 'location': 'Vadodara, Gujarat'},
    {'name': 'Tata Chemicals Mithapur', 'location': 'Dwarka, Gujarat'},
    {'name': 'Aarti Industries Vapi', 'location': 'Vapi, Gujarat'},
    {'name': 'UPL Ltd Ankleshwar', 'location': 'Ankleshwar, Gujarat'},
    {'name': 'Adani Wilmar Mundra', 'location': 'Mundra Port, Gujarat'},
    {'name': 'Adani Ports Hazira', 'location': 'Hazira, Gujarat'},
    {
      'name': 'Mundra Port Container Terminal',
      'location': 'Mundra Port, Gujarat'
    },
    {'name': 'Kandla Port Trust', 'location': 'Kandla, Gujarat'},
    {'name': 'Dahej Port Authority', 'location': 'Dahej, Gujarat'},
    {'name': 'JNPT (Nhava Sheva)', 'location': 'Navi Mumbai, Maharashtra'},
    {
      'name': 'Haldia Petrochemicals Ltd',
      'location': 'Haldia Port, West Bengal'
    },
    {'name': 'Vizag Steel Plant', 'location': 'Visakhapatnam, Andhra Pradesh'},
    {'name': 'NTPC Sipat Thermal Plant', 'location': 'Raipur, Chhattisgarh'},
    {'name': 'Bhilai Steel Plant', 'location': 'Durg, Chhattisgarh'},
    {'name': 'Bokaro Steel City', 'location': 'Bokaro, Jharkhand'},
    {'name': 'Tata Steel Jamshedpur', 'location': 'Jamshedpur, Jharkhand'},
    {'name': 'BPCL Bina Refinery', 'location': 'Sagar, Madhya Pradesh'},
    {'name': 'HMEL Bathinda Refinery', 'location': 'Bathinda, Punjab'},
    {'name': 'Numaligarh Refinery', 'location': 'Golaghat, Assam'},
    {'name': 'Mangalore Refinery MRPL', 'location': 'Mangaluru, Karnataka'},
    {'name': 'Chennai Petroleum CPCL', 'location': 'Chennai, Tamil Nadu'},
    {'name': 'CPCL Manali Refinery', 'location': 'Chennai, Tamil Nadu'},
    {
      'name': 'Coromandel International',
      'location': 'Visakhapatnam, Andhra Pradesh'
    },
    {'name': 'Nagarjuna Fertilizers', 'location': 'Kakinada, Andhra Pradesh'},
    {'name': 'Indian Potash Ltd - Chennai', 'location': 'Chennai, Tamil Nadu'},
    {'name': 'BASF India Ltd - Dahej', 'location': 'Dahej, Gujarat'},
    {'name': 'Linde India Ltd - Hazira', 'location': 'Hazira, Gujarat'},
    {'name': 'Air Products India - Vadodara', 'location': 'Vadodara, Gujarat'},
    {'name': 'Sun Pharma - Halol', 'location': 'Halol, Gujarat'},
    {'name': 'Lupin Ltd - Ankleshwar', 'location': 'Ankleshwar, Gujarat'},
    {'name': 'Torrent Pharma - Ahmedabad', 'location': 'Ahmedabad, Gujarat'},
    {'name': 'Essar Oil Terminal Vadinar', 'location': 'Jamnagar, Gujarat'},
    {
      'name': 'Gujarat Narmada Valley Fertilizers',
      'location': 'Bharuch, Gujarat'
    },
    {'name': 'Hindustan Petroleum Terminal', 'location': 'Mahul, Mumbai'},
    {'name': 'Panipat Textile Mills', 'location': 'Panipat, Haryana'},
    {'name': 'Dalmia Bharat Cement', 'location': 'Dalmiapuram, Tamil Nadu'},
    {
      'name': 'UltraTech Cement - Nathdwara',
      'location': 'Rajsamand, Rajasthan'
    },
    {'name': 'JK Cement Works Mangrol', 'location': 'Mangrol, Rajasthan'},
    {'name': 'Ambuja Cement Darlaghat', 'location': 'Solan, Himachal Pradesh'},
    {'name': 'ACC Cement Gagal', 'location': 'Bilaspur, Himachal Pradesh'},
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    // Use onChanged in build() â€” not addListener â€” so programmatic text set doesn't trigger search
    _focus.addListener(() {
      if (!_focus.hasFocus) _rmOverlay();
    });
  }

  Future<List<Map<String, String>>> _placesAutocomplete(String q) async {
    try {
      // Use Google Places Autocomplete for ANY company/factory
      final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(q)}'
          '&types=establishment'
          '&region=in'
          '&language=en'
          '&key=${AppConfig.googleMapsApiKey}';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'OK') {
          return (data['predictions'] as List)
              .take(6)
              .map<Map<String, String>>((p) => {
                    'name': p['description'] as String,
                    'placeId': p['place_id'] as String,
                  })
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  void _onChange(String typed) {
    if (_selecting) return;
    if (_deb?.isActive ?? false) _deb!.cancel();
    _deb = Timer(const Duration(milliseconds: 400), () async {
      final q = typed.trim();
      if (q.length < 2) {
        _rmOverlay();
        return;
      }
      List<Map<String, String>> results = [];
      // PRIMARY: Google Places â€” returns every company on Google Maps
      final apiResults = await RoutingEngine.getCompanySuggestions(q);
      if (apiResults.isNotEmpty) {
        results = apiResults;
      }
      // FALLBACK: local list if Google returns nothing (no API key / offline)
      if (results.isEmpty) {
        results = kKnownFactories
            .where((f) =>
                f['name']!.toLowerCase().contains(q.toLowerCase()) ||
                (f['location'] ?? '').toLowerCase().contains(q.toLowerCase()))
            .take(8)
            .map((f) => {
                  'name': f['name']!,
                  'location': f['location'] ?? '',
                  'placeId': ''
                })
            .toList();
      }
      if (!mounted) return;
      _sugg = results;
      if (results.isEmpty) {
        _rmOverlay();
        return;
      }
      _rmOverlay();
      _showOverlay();
    });
  }

  @override
  void dispose() {
    _rmOverlay();
    _deb?.cancel();
    _focus.dispose();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  OverlayEntry? _overlay;
  final FocusNode _focus = FocusNode();
  final LayerLink _link = LayerLink();

  void _showOverlay() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    _overlay = OverlayEntry(
        builder: (_) => Positioned(
              width: box.size.width,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                offset: Offset(0, box.size.height + 4),
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _sugg.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: const Color(0xFF000000)),
                        itemBuilder: (_, i) {
                          final s = _sugg[i];
                          return ListTile(
                              dense: true,
                              leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                      color: widget.iconColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Icon(Icons.factory,
                                      color: widget.iconColor, size: 14)),
                              title: Text(s['name'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: Color(0xFF000000)),
                                  overflow: TextOverflow.ellipsis),
                              subtitle: (s['location'] ?? '').isNotEmpty
                                  ? Text(s['location']!,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey))
                                  : null,
                              onTap: () {
                                _selecting = true;
                                _rmOverlay();
                                _deb?.cancel();
                                _ctrl.text = s['name'] ?? '';
                                widget.onSelected(
                                    s['name'] ?? '', s['placeId'] ?? '');
                                _focus.unfocus();
                                Future.delayed(
                                    const Duration(milliseconds: 400), () {
                                  if (mounted) _selecting = false;
                                });
                              });
                        }),
                  ),
                ),
              ),
            ));
    Overlay.of(context).insert(_overlay!);
  }

  void _rmOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
        link: _link,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onChange,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(Icons.factory, color: widget.iconColor, size: 20),
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _ctrl.clear();
                      _rmOverlay();
                    })
                : Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.iconColor, width: 2)),
          ),
        ),
      );
}

class CitySearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String label, initialValue;
  final IconData icon;
  final Color iconColor;
  final Function(String city, String state, String placeId) onCitySelected;
  const CitySearchField(
      {super.key,
      this.controller,
      required this.label,
      required this.icon,
      required this.iconColor,
      this.initialValue = "",
      required this.onCitySelected});
  @override
  State<CitySearchField> createState() => _CitySearchFieldState();
}

class _CitySearchFieldState extends State<CitySearchField> {
  late TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  OverlayEntry? _overlay;
  List<Map<String, String>> _sugg = [];
  Timer? _deb;
  final LayerLink _link = LayerLink();
  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    if (widget.initialValue.isNotEmpty && _ctrl.text.isEmpty) {
      _ctrl.text = widget.initialValue;
    }
    // NO addListener â€” use onChanged in TextField so only user-typing triggers it
    _focus.addListener(() {
      if (!_focus.hasFocus) _removeOverlay();
    });
  }

  void _onUserTyped(String value) {
    // Only called when USER types â€” not when we set _ctrl.text programmatically
    if (_deb?.isActive ?? false) _deb!.cancel();
    final q = value.trim();
    if (q.length < 2) {
      _removeOverlay();
      return;
    }
    // Immediate local results for instant feedback
    final localQ = q.toLowerCase();
    final local = kIndianCities
        .where((c) =>
            c['city']!.toLowerCase().startsWith(localQ) ||
            c['city']!.toLowerCase().contains(localQ) ||
            c['state']!.toLowerCase().contains(localQ))
        .toList();
    local.sort((a, b) {
      final aS = a['city']!.toLowerCase().startsWith(localQ) ? 0 : 1;
      final bS = b['city']!.toLowerCase().startsWith(localQ) ? 0 : 1;
      return aS - bS;
    });
    if (local.isNotEmpty) {
      _sugg = local
          .take(10)
          .map((c) => {
                'city': c['city']!,
                'state': c['state']!,
                'full': c['full']!,
                'placeId': ''
              })
          .toList();
      _removeOverlay();
      _showOverlay();
    }
    // Then fetch Google Places in background for more complete results
    _deb = Timer(const Duration(milliseconds: 400), () async {
      final results = await RoutingEngine.getCitySuggestions(_ctrl.text.trim());
      if (!mounted || _ctrl.text.trim().length < 2) return;
      if (results.isNotEmpty) {
        _sugg = results;
        _removeOverlay();
        _showOverlay();
      }
    });
  }

  void _showOverlay() {
    final ctx = context;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    _overlay = OverlayEntry(
        builder: (_) => Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                offset: Offset(0, size.height + 4),
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _sugg.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: const Color(0xFF000000)),
                      itemBuilder: (_, i) {
                        final s = _sugg[i];
                        return ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: widget.iconColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: Icon(widget.icon,
                                color: widget.iconColor, size: 14),
                          ),
                          title: Text(s['city'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFF000000))),
                          subtitle: (s['state'] ?? '').isNotEmpty
                              ? Text('${s['state']}, India',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey))
                              : null,
                          trailing: Text(s['state'] ?? '',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: widget.iconColor,
                                  fontWeight: FontWeight.bold)),
                          onTap: () {
                            _deb?.cancel();
                            _removeOverlay();
                            _ctrl.text = s['full'] ??
                                '${s['city'] ?? ''}, ${s['state'] ?? ''}';
                            _focus.unfocus();
                            widget.onCitySelected(s['city'] ?? '',
                                s['state'] ?? '', s['placeId'] ?? '');
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ));
    Overlay.of(ctx).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    _deb?.cancel();
    _focus.dispose();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
        link: _link,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onUserTyped,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon, color: widget.iconColor, size: 20),
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _ctrl.clear();
                      _removeOverlay();
                    })
                : Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.iconColor, width: 2),
            ),
          ),
        ),
      );
}

// ================================================================
// TRIP DETAIL SCREEN
// ================================================================
class TripDetailScreen extends StatefulWidget {
  final TripLedger ledger;
  final UserProfile userProfile;
  final SubscriptionInfo subscription;
  final List<Driver> drivers;
  final Function(TripLedger) onUpdateLedger;
  final Function(KredXApplication) onKredXApply;
  const TripDetailScreen(
      {super.key,
      required this.ledger,
      required this.userProfile,
      required this.subscription,
      required this.drivers,
      required this.onUpdateLedger,
      required this.onKredXApply});
  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late TripLedger _l;
  @override
  void initState() {
    super.initState();
    _l = widget.ledger;
  }

  String _f(double v) => v.toStringAsFixed(2);

  pw.Widget _cell(String t,
          {bool hdr = false,
          bool bold = false,
          pw.TextAlign? align,
          PdfColor? col}) =>
      pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: pw.Text(t,
              textAlign: align,
              style: pw.TextStyle(
                  fontSize: hdr ? 9 : 10,
                  fontWeight:
                      hdr || bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: hdr
                      ? const PdfColor(0.1, 0.23, 0.1)
                      : (col ?? const PdfColor(0.15, 0.15, 0.15)))));
  pw.Widget _pRow(String l, String v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(children: [
        pw.Text("$l: ",
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor(0.4, 0.4, 0.4))),
        pw.Flexible(child: pw.Text(v, style: const pw.TextStyle(fontSize: 9)))
      ]));

  Future<void> _shareLR() async {
    if (!widget.subscription.canExportPDF) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          content: Text("PDF Export requires PRO plan or above")));
      return;
    }
    final pdf = pw.Document();
    final up = widget.userProfile;
    final l = _l;

    pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) {
          pw.Widget borderBox(pw.Widget child, {pw.EdgeInsets? pad}) =>
              pw.Container(
                  padding: pad ?? const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                          color: const PdfColor(0.75, 0.75, 0.75), width: 0.6)),
                  child: child);

          pw.Widget label(String t) => pw.Text(t.toUpperCase(),
              style: const pw.TextStyle(
                  fontSize: 7, color: PdfColor(0.5, 0.5, 0.5)));
          pw.Widget value(String t, {bool bold = false, double size = 10}) =>
              pw.Text(t,
                  style: pw.TextStyle(
                      fontSize: size,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal));

          final balance = l.freightBilled - l.paymentReceived;
          final fromCity = l.loadingPoint.isNotEmpty
              ? l.loadingPoint
              : l.route.split('â†’').first.trim();
          final toCity = l.unloadingPoint.isNotEmpty
              ? l.unloadingPoint
              : l.route.split('â†’').last.trim();

          return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // â”€â”€ HEADER â”€â”€
                pw.Container(
                    color: const PdfColor(0.05, 0.09, 0.16),
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                              child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                pw.Text(up.companyName.toUpperCase(),
                                    style: pw.TextStyle(
                                        fontSize: 18,
                                        fontWeight: pw.FontWeight.bold,
                                        color: const PdfColor(0.1, 0.23, 0.1),
                                        letterSpacing: 1)),
                                pw.SizedBox(height: 2),
                                if (up.address.isNotEmpty)
                                  pw.Text(up.address,
                                      style: const pw.TextStyle(
                                          fontSize: 8,
                                          color: PdfColor(0.7, 0.8, 0.9))),
                                pw.Text(
                                    "Tel: ${up.phone}${up.gstin.isNotEmpty ? '  |  GST: ${up.gstin}' : ''}",
                                    style: const pw.TextStyle(
                                        fontSize: 8,
                                        color: PdfColor(0.7, 0.8, 0.9))),
                              ])),
                          pw.SizedBox(width: 24),
                          pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    color: const PdfColor(0.23, 0.51, 0.96),
                                    child: pw.Text("LORRY RECEIPT",
                                        style: pw.TextStyle(
                                            fontSize: 13,
                                            fontWeight: pw.FontWeight.bold,
                                            color:
                                                const PdfColor(0.1, 0.23, 0.1),
                                            letterSpacing: 1.5))),
                                pw.SizedBox(height: 5),
                                pw.Text("LR No:  LR-${l.id}",
                                    style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 10,
                                        color: const PdfColor(0.1, 0.23, 0.1))),
                                pw.Text("Date:  ${l.date}",
                                    style: const pw.TextStyle(
                                        fontSize: 9,
                                        color: PdfColor(0.75, 0.75, 0.85))),
                              ]),
                        ])),

                // â”€â”€ FROM / TO â”€â”€
                pw.Row(children: [
                  pw.Expanded(
                      child: borderBox(
                          pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Row(children: [
                                  pw.Container(
                                      width: 3,
                                      height: 3,
                                      decoration: const pw.BoxDecoration(
                                          shape: pw.BoxShape.circle,
                                          color: PdfColor(0.0, 0.6, 0.3))),
                                  pw.SizedBox(width: 4),
                                  pw.Text("CONSIGNOR (FROM)",
                                      style: const pw.TextStyle(
                                          fontSize: 7,
                                          color: PdfColor(0.5, 0.5, 0.5)))
                                ]),
                                pw.SizedBox(height: 4),
                                value(l.partyName.toUpperCase(),
                                    bold: true, size: 12),
                                value(fromCity, size: 9),
                                if (l.loadingState.isNotEmpty)
                                  value(l.loadingState, size: 9),
                                if (l.consignorPhone.isNotEmpty)
                                  value("Tel: ${l.consignorPhone}", size: 8),
                                if (l.consignorGstin.isNotEmpty)
                                  value("GSTIN: ${l.consignorGstin}", size: 8),
                              ]),
                          pad: const pw.EdgeInsets.all(10))),
                  pw.Expanded(
                      child: borderBox(
                          pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Row(children: [
                                  pw.Container(
                                      width: 3,
                                      height: 3,
                                      decoration: const pw.BoxDecoration(
                                          shape: pw.BoxShape.circle,
                                          color: PdfColor(0.8, 0.1, 0.1))),
                                  pw.SizedBox(width: 4),
                                  pw.Text("CONSIGNEE (TO)",
                                      style: const pw.TextStyle(
                                          fontSize: 7,
                                          color: PdfColor(0.5, 0.5, 0.5)))
                                ]),
                                pw.SizedBox(height: 4),
                                value(toCity.toUpperCase(),
                                    bold: true, size: 12),
                                if (l.unloadingState.isNotEmpty)
                                  value(l.unloadingState, size: 9),
                                value("Delivery at: $toCity", size: 8),
                              ]),
                          pad: const pw.EdgeInsets.all(10))),
                ]),

                // â”€â”€ SHIPMENT DETAILS â”€â”€
                borderBox(
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("SHIPMENT DETAILS",
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                  color: const PdfColor(0.05, 0.09, 0.16))),
                          pw.SizedBox(height: 8),
                          pw.Table(
                              border: pw.TableBorder.all(
                                  color: const PdfColor(0.88, 0.88, 0.88),
                                  width: 0.5),
                              columnWidths: {
                                0: const pw.FlexColumnWidth(2),
                                1: const pw.FlexColumnWidth(3),
                                2: const pw.FlexColumnWidth(2),
                                3: const pw.FlexColumnWidth(3),
                              },
                              children: [
                                pw.TableRow(
                                    decoration: const pw.BoxDecoration(
                                        color: PdfColor(0.93, 0.95, 0.99)),
                                    children: [
                                      pw.Padding(
                                          padding: const pw.EdgeInsets.all(5),
                                          child: pw.Text("Vehicle No",
                                              style: pw.TextStyle(
                                                  fontSize: 8,
                                                  fontWeight:
                                                      pw.FontWeight.bold))),
                                      pw.Padding(
                                          padding: const pw.EdgeInsets.all(5),
                                          child: pw.Text(l.vehicleNo,
                                              style: pw.TextStyle(
                                                  fontSize: 9,
                                                  fontWeight:
                                                      pw.FontWeight.bold))),
                                      pw.Padding(
                                          padding: const pw.EdgeInsets.all(5),
                                          child: pw.Text("Driver",
                                              style: pw.TextStyle(
                                                  fontSize: 8,
                                                  fontWeight:
                                                      pw.FontWeight.bold))),
                                      pw.Padding(
                                          padding: const pw.EdgeInsets.all(5),
                                          child: pw.Text(l.driverName ?? "â€”",
                                              style: const pw.TextStyle(
                                                  fontSize: 9))),
                                    ]),
                                pw.TableRow(children: [
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text("Material",
                                          style: pw.TextStyle(
                                              fontSize: 8,
                                              fontWeight: pw.FontWeight.bold))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text(l.materialName,
                                          style:
                                              const pw.TextStyle(fontSize: 9))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text("Weight",
                                          style: pw.TextStyle(
                                              fontSize: 8,
                                              fontWeight: pw.FontWeight.bold))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text(
                                          l.weightTons > 0
                                              ? "${l.weightTons} ${l.weightUnit}"
                                              : "As per weighbridge",
                                          style:
                                              const pw.TextStyle(fontSize: 9))),
                                ]),
                                pw.TableRow(children: [
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text("E-Way Bill",
                                          style: pw.TextStyle(
                                              fontSize: 8,
                                              fontWeight: pw.FontWeight.bold))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text(l.eWayBillNo,
                                          style:
                                              const pw.TextStyle(fontSize: 9))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text("Distance",
                                          style: pw.TextStyle(
                                              fontSize: 8,
                                              fontWeight: pw.FontWeight.bold))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text(
                                          l.distanceKm > 0
                                              ? "${l.distanceKm.toStringAsFixed(0)} km"
                                              : "â€”",
                                          style:
                                              const pw.TextStyle(fontSize: 9))),
                                ]),
                                if (l.materialInvoiceNo.isNotEmpty)
                                  pw.TableRow(children: [
                                    pw.Padding(
                                        padding: const pw.EdgeInsets.all(5),
                                        child: pw.Text("Invoice No.",
                                            style: pw.TextStyle(
                                                fontSize: 8,
                                                fontWeight:
                                                    pw.FontWeight.bold))),
                                    pw.Padding(
                                        padding: const pw.EdgeInsets.all(5),
                                        child: pw.Text(l.materialInvoiceNo,
                                            style: const pw.TextStyle(
                                                fontSize: 9))),
                                    pw.Padding(
                                        padding: const pw.EdgeInsets.all(5),
                                        child: pw.Text("Weight",
                                            style: pw.TextStyle(
                                                fontSize: 8,
                                                fontWeight:
                                                    pw.FontWeight.bold))),
                                    pw.Padding(
                                        padding: const pw.EdgeInsets.all(5),
                                        child: pw.Text(
                                            l.weightTons > 0
                                                ? "${l.weightTons} ${l.weightUnit}"
                                                : "As per weighbridge",
                                            style: const pw.TextStyle(
                                                fontSize: 9))),
                                  ]),
                                pw.TableRow(children: [
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text("Loading Date",
                                          style: pw.TextStyle(
                                              fontSize: 8,
                                              fontWeight: pw.FontWeight.bold))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text(l.date,
                                          style:
                                              const pw.TextStyle(fontSize: 9))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text("Pay Terms",
                                          style: pw.TextStyle(
                                              fontSize: 8,
                                              fontWeight: pw.FontWeight.bold))),
                                  pw.Padding(
                                      padding: const pw.EdgeInsets.all(5),
                                      child: pw.Text(
                                          "${l.paymentTermsDays} Days from delivery",
                                          style:
                                              const pw.TextStyle(fontSize: 9))),
                                ]),
                              ]),
                        ]),
                    pad: const pw.EdgeInsets.all(10)),

                // â”€â”€ FREIGHT SUMMARY â”€â”€
                pw.SizedBox(height: 4),
                pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                          flex: 3,
                          child: borderBox(
                              pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text("FREIGHT DETAILS",
                                        style: pw.TextStyle(
                                            fontSize: 9,
                                            fontWeight: pw.FontWeight.bold,
                                            color: const PdfColor(
                                                0.05, 0.09, 0.16))),
                                    pw.SizedBox(height: 8),
                                    pw.Row(
                                        mainAxisAlignment:
                                            pw.MainAxisAlignment.spaceBetween,
                                        children: [
                                          pw.Text("Agreed Freight:",
                                              style: pw.TextStyle(
                                                  fontSize: 9,
                                                  fontWeight:
                                                      pw.FontWeight.bold)),
                                          pw.Text(
                                              "INR ${l.freightBilled.toStringAsFixed(2)}",
                                              style: pw.TextStyle(
                                                  fontSize: 9,
                                                  fontWeight:
                                                      pw.FontWeight.bold))
                                        ]),
                                    if (l.paymentReceived > 0) ...[
                                      pw.SizedBox(height: 3),
                                      pw.Row(
                                          mainAxisAlignment:
                                              pw.MainAxisAlignment.spaceBetween,
                                          children: [
                                            pw.Text("Advance Paid:",
                                                style: const pw.TextStyle(
                                                    fontSize: 9,
                                                    color: PdfColor(
                                                        0.4, 0.4, 0.4))),
                                            pw.Text(
                                                "INR ${l.paymentReceived.toStringAsFixed(2)}",
                                                style: const pw.TextStyle(
                                                    fontSize: 9,
                                                    color: PdfColor(
                                                        0.5, 0.3, 0.0)))
                                          ]),
                                    ],
                                    pw.SizedBox(height: 6),
                                    pw.Container(
                                        color: const PdfColor(0.05, 0.09, 0.16),
                                        padding: const pw.EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        child: pw.Row(
                                            mainAxisAlignment: pw
                                                .MainAxisAlignment.spaceBetween,
                                            children: [
                                              pw.Text("BALANCE ON DELIVERY:",
                                                  style: pw.TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          pw.FontWeight.bold,
                                                      color: const PdfColor(
                                                          0.1, 0.23, 0.1))),
                                              pw.Text(
                                                  "INR ${balance.toStringAsFixed(2)}",
                                                  style: pw.TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          pw.FontWeight.bold,
                                                      color: balance > 0
                                                          ? const PdfColor(
                                                              0.0, 0.9, 0.4)
                                                          : const PdfColor(
                                                              0.1, 0.23, 0.1))),
                                            ])),
                                  ]),
                              pad: const pw.EdgeInsets.all(10))),
                      pw.SizedBox(width: 4),
                      pw.Expanded(
                          flex: 2,
                          child: pw.Container(
                              height: double.infinity,
                              padding: const pw.EdgeInsets.all(10),
                              decoration: pw.BoxDecoration(
                                  border: pw.Border.all(
                                      color: const PdfColor(0.75, 0.75, 0.75),
                                      width: 0.6)),
                              child: pw.Column(
                                  mainAxisAlignment:
                                      pw.MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.center,
                                  children: [
                                    pw.Text("AUTHORISED SIGNATORY",
                                        style: const pw.TextStyle(
                                            fontSize: 8,
                                            color: PdfColor(0.5, 0.5, 0.5))),
                                    pw.SizedBox(height: 30),
                                    pw.Container(
                                        width: 100,
                                        height: 0.7,
                                        color: const PdfColor(0.3, 0.3, 0.3)),
                                    pw.SizedBox(height: 4),
                                    pw.Text(up.companyName,
                                        style: pw.TextStyle(
                                            fontSize: 8,
                                            fontWeight: pw.FontWeight.bold)),
                                    pw.Text("Stamp & Seal",
                                        style: const pw.TextStyle(
                                            fontSize: 7,
                                            color: PdfColor(0.6, 0.6, 0.6))),
                                  ]))),
                    ]),

                // â”€â”€ PART LOAD ITEMS TABLE â”€â”€
                if (l.invoiceItems.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text("PART LOAD CONSIGNMENT DETAILS",
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor(0.05, 0.09, 0.16))),
                  pw.SizedBox(height: 4),
                  pw.Table(
                      border: pw.TableBorder.all(
                          color: const PdfColor(0.85, 0.85, 0.85), width: 0.5),
                      columnWidths: {
                        0: const pw.FixedColumnWidth(20),
                        1: const pw.FlexColumnWidth(3),
                        2: const pw.FlexColumnWidth(2),
                        3: const pw.FlexColumnWidth(2)
                      },
                      children: [
                        pw.TableRow(
                            decoration: const pw.BoxDecoration(
                                color: PdfColor(0.1, 0.1, 0.1)),
                            children: ['#', 'Material', 'Invoice No.', 'Weight']
                                .map((h) => pw.Padding(
                                    padding: const pw.EdgeInsets.all(4),
                                    child: pw.Text(h,
                                        style: pw.TextStyle(
                                            fontSize: 8,
                                            fontWeight: pw.FontWeight.bold,
                                            color: const PdfColor(
                                                0.1, 0.23, 0.1)))))
                                .toList()),
                        ...l.invoiceItems.asMap().entries.map((e) =>
                            pw.TableRow(children: [
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text("${e.key + 1}",
                                      style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(e.value.materialName,
                                      style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                      e.value.invoiceNo.isNotEmpty
                                          ? e.value.invoiceNo
                                          : "â€”",
                                      style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                      "${e.value.weight} ${e.value.weightUnit}",
                                      style: const pw.TextStyle(fontSize: 8))),
                            ])),
                      ]),
                ],

                // â”€â”€ TERMS â”€â”€
                pw.SizedBox(height: 8),
                pw.Container(
                    color: const PdfColor(0.97, 0.97, 0.97),
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("Terms & Conditions",
                              style: pw.TextStyle(
                                  fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 3),
                          pw.Text(
                              "1. Goods received in apparent good order and condition.  2. Carrier's liability limited as per Carriage by Road Act.  3. Subject to ${up.address.split(',').last.trim()} jurisdiction.  4. Interest @ 2% per month on delayed payments.  5. E. & O.E.",
                              style: const pw.TextStyle(
                                  fontSize: 7.5,
                                  color: PdfColor(0.4, 0.4, 0.4))),
                          if (up.bankAccount.isNotEmpty) ...[
                            pw.SizedBox(height: 4),
                            pw.Text(
                                "Bank: ${up.bankName}  |  A/C No: ${up.bankAccount}  |  IFSC: ${up.bankIfsc}",
                                style: pw.TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: const PdfColor(0.2, 0.2, 0.5)))
                          ],
                        ])),

                if (l.lrNotes.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      color: const PdfColor(1.0, 0.97, 0.88),
                      child: pw.Text("Remarks: ${l.lrNotes}",
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColor(0.4, 0.3, 0.0)))),
                ],

                // DRIVER COPY footer line
                pw.SizedBox(height: 8),
                pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          color: const PdfColor(0.9, 0.9, 0.9),
                          child: pw.Text("DRIVER COPY",
                              style: const pw.TextStyle(
                                  fontSize: 8,
                                  color: PdfColor(0.4, 0.4, 0.4)))),
                      pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          color: const PdfColor(0.9, 0.9, 0.9),
                          child: pw.Text("CONSIGNOR COPY",
                              style: const pw.TextStyle(
                                  fontSize: 8,
                                  color: PdfColor(0.4, 0.4, 0.4)))),
                      pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          color: const PdfColor(0.9, 0.9, 0.9),
                          child: pw.Text("OFFICE COPY",
                              style: const pw.TextStyle(
                                  fontSize: 8,
                                  color: PdfColor(0.4, 0.4, 0.4)))),
                    ]),
              ]);
        }));

    try {
      await Printing.sharePdf(
          bytes: await pdf.save(),
          filename: 'LR_${l.id}_${l.partyName.replaceAll(' ', '_')}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("PDF Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _shareInvoice() async {
    if (!widget.subscription.canExportPDF) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          content: Text("PDF Export requires PRO or BUSINESS plan")));
      return;
    }
    final pdf = pw.Document();
    final up = widget.userProfile;
    final l = _l;
    final cgst = l.gstType == GstType.cgstSgst ? l.gstAmount / 2 : 0.0;
    final sgst = l.gstType == GstType.cgstSgst ? l.gstAmount / 2 : 0.0;
    final igst = l.gstType == GstType.igst ? l.gstAmount : 0.0;
    pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(up.companyName.toUpperCase(),
                                  style: pw.TextStyle(
                                      fontSize: 20,
                                      fontWeight: pw.FontWeight.bold,
                                      color: const PdfColor(0.05, 0.09, 0.16))),
                              pw.SizedBox(height: 4),
                              pw.Text(up.address,
                                  style: const pw.TextStyle(
                                      fontSize: 10,
                                      color: PdfColor(0.4, 0.4, 0.4))),
                              pw.Text("Tel: ${up.phone}",
                                  style: const pw.TextStyle(
                                      fontSize: 10,
                                      color: PdfColor(0.4, 0.4, 0.4))),
                              if (up.gstin.isNotEmpty &&
                                  up.gstin != "Unregistered")
                                pw.Text("GSTIN: ${up.gstin}",
                                    style: pw.TextStyle(
                                        fontSize: 10,
                                        fontWeight: pw.FontWeight.bold)),
                              if (up.email.isNotEmpty)
                                pw.Text("Email: ${up.email}",
                                    style: const pw.TextStyle(
                                        fontSize: 10,
                                        color: PdfColor(0.4, 0.4, 0.4)))
                            ]),
                        pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: pw.BoxDecoration(
                                      color: const PdfColor(0.05, 0.09, 0.16),
                                      borderRadius:
                                          pw.BorderRadius.circular(6)),
                                  child: pw.Text("TAX INVOICE",
                                      style: pw.TextStyle(
                                          fontSize: 14,
                                          fontWeight: pw.FontWeight.bold,
                                          color:
                                              const PdfColor(0.1, 0.23, 0.1)))),
                              pw.SizedBox(height: 8),
                              pw.Text("Invoice No: INV-${l.id}",
                                  style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 11)),
                              pw.Text("Date: ${l.date}",
                                  style: const pw.TextStyle(
                                      fontSize: 10,
                                      color: PdfColor(0.4, 0.4, 0.4))),
                              pw.Text("Due: ${l.paymentTermsDays} Days",
                                  style: const pw.TextStyle(
                                      fontSize: 10,
                                      color: PdfColor(0.4, 0.4, 0.4)))
                            ]),
                      ]),
                  pw.SizedBox(height: 16),
                  pw.Divider(
                      color: const PdfColor(0.05, 0.09, 0.16), thickness: 1.5),
                  pw.SizedBox(height: 14),
                  pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                            child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                              pw.Text("BILL TO:",
                                  style: const pw.TextStyle(
                                      fontSize: 9,
                                      color: PdfColor(0.5, 0.5, 0.5))),
                              pw.SizedBox(height: 4),
                              pw.Text(l.partyName.toUpperCase(),
                                  style: pw.TextStyle(
                                      fontSize: 15,
                                      fontWeight: pw.FontWeight.bold)),
                              if (l.consignorGstin.isNotEmpty)
                                pw.Text("GSTIN: ${l.consignorGstin}",
                                    style: const pw.TextStyle(fontSize: 10)),
                              if (l.consignorPhone.isNotEmpty)
                                pw.Text("Phone: ${l.consignorPhone}",
                                    style: const pw.TextStyle(fontSize: 10))
                            ])),
                        pw.SizedBox(width: 20),
                        pw.Expanded(
                            child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                              pw.Text("SHIPMENT:",
                                  style: const pw.TextStyle(
                                      fontSize: 9,
                                      color: PdfColor(0.5, 0.5, 0.5))),
                              pw.SizedBox(height: 4),
                              _pRow("Route",
                                  "${l.loadingPoint.isNotEmpty ? l.loadingPoint : ''} â†’ ${l.unloadingPoint.isNotEmpty ? l.unloadingPoint : l.route.split('â†’').last.trim()}"),
                              _pRow("Vehicle", l.vehicleNo),
                              _pRow("Material", l.materialName),
                              if (l.weightTons > 0)
                                _pRow("Weight",
                                    "${l.weightTons} ${l.weightUnit}"),
                              _pRow("E-Way", l.eWayBillNo),
                              if (l.driverName != null)
                                _pRow("Driver", l.driverName!)
                            ])),
                      ]),
                  pw.SizedBox(height: 16),
                  pw.Table(
                      border: pw.TableBorder.all(
                          color: const PdfColor(0.85, 0.85, 0.85), width: 0.8),
                      columnWidths: {
                        0: const pw.FixedColumnWidth(28),
                        1: const pw.FlexColumnWidth(5),
                        2: const pw.FlexColumnWidth(2)
                      },
                      children: [
                        pw.TableRow(
                            decoration: const pw.BoxDecoration(
                                color: PdfColor(0.05, 0.09, 0.16)),
                            children: [
                              _cell("#", hdr: true, align: pw.TextAlign.center),
                              _cell("DESCRIPTION", hdr: true),
                              _cell("AMOUNT (â‚¹)",
                                  hdr: true, align: pw.TextAlign.right)
                            ]),
                        pw.TableRow(children: [
                          _cell("1", align: pw.TextAlign.center),
                          _cell(
                              "Freight for ${l.materialName}\n${l.route}\nVehicle: ${l.vehicleNo}${l.weightTons > 0 ? ' | ${l.weightTons} ${l.weightUnit}' : ''}"),
                          _cell(_f(l.taxableFreight), align: pw.TextAlign.right)
                        ]),
                        if (l.gstType == GstType.cgstSgst) ...[
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("CGST @ ${l.gstRate / 2}%"),
                            _cell(_f(cgst), align: pw.TextAlign.right)
                          ]),
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("SGST @ ${l.gstRate / 2}%"),
                            _cell(_f(sgst), align: pw.TextAlign.right)
                          ])
                        ],
                        if (l.gstType == GstType.igst)
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("IGST @ ${l.gstRate}%"),
                            _cell(_f(igst), align: pw.TextAlign.right)
                          ]),
                        // Correct invoice table â€” no duplicates
                        pw.TableRow(
                            decoration: const pw.BoxDecoration(
                                color: PdfColor(0.93, 0.97, 1.0)),
                            children: [
                              _cell("", align: pw.TextAlign.center),
                              _cell("TAXABLE FREIGHT", bold: true),
                              _cell("INR ${_f(l.taxableFreight)}",
                                  align: pw.TextAlign.right, bold: true)
                            ]),
                        if (l.gstType == GstType.cgstSgst) ...[
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("Add: CGST @ ${l.gstRate / 2}%"),
                            _cell("INR ${_f(l.gstAmount / 2)}",
                                align: pw.TextAlign.right)
                          ]),
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("Add: SGST @ ${l.gstRate / 2}%"),
                            _cell("INR ${_f(l.gstAmount / 2)}",
                                align: pw.TextAlign.right)
                          ]),
                        ],
                        if (l.gstType == GstType.igst)
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("Add: IGST @ ${l.gstRate}%"),
                            _cell("INR ${_f(l.gstAmount)}",
                                align: pw.TextAlign.right)
                          ]),
                        pw.TableRow(
                            decoration: const pw.BoxDecoration(
                                color: PdfColor(0.93, 0.97, 1.0)),
                            children: [
                              _cell("", align: pw.TextAlign.center),
                              _cell("GROSS INVOICE TOTAL", bold: true),
                              _cell("INR ${_f(l.freightBilled + l.gstAmount)}",
                                  align: pw.TextAlign.right, bold: true)
                            ]),
                        if (l.tdsDeduction > 0)
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("Less: TDS u/s 194C @ deducted"),
                            _cell("(INR ${_f(l.tdsDeduction)})",
                                align: pw.TextAlign.right,
                                col: const PdfColor(0.6, 0.1, 0.1))
                          ]),
                        if (l.penalties > 0)
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("Less: Penalties / Damages"),
                            _cell("(INR ${_f(l.penalties)})",
                                align: pw.TextAlign.right,
                                col: const PdfColor(0.6, 0.1, 0.1))
                          ]),
                        if (l.materialLoss > 0)
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("Less: Material Loss"),
                            _cell("(INR ${_f(l.materialLoss)})",
                                align: pw.TextAlign.right,
                                col: const PdfColor(0.6, 0.1, 0.1))
                          ]),
                        if (l.paymentReceived > 0)
                          pw.TableRow(
                              decoration: const pw.BoxDecoration(
                                  color: PdfColor(1.0, 0.97, 0.90)),
                              children: [
                                _cell("", align: pw.TextAlign.center),
                                _cell("Less: Advance Received", bold: true),
                                _cell("(INR ${_f(l.paymentReceived)})",
                                    align: pw.TextAlign.right,
                                    bold: true,
                                    col: const PdfColor(0.5, 0.3, 0.0))
                              ]),
                        pw.TableRow(
                            decoration: const pw.BoxDecoration(
                                color: PdfColor(0.88, 0.97, 0.88)),
                            children: [
                              _cell("", align: pw.TextAlign.center),
                              _cell("NET BALANCE PAYABLE", bold: true),
                              _cell("INR ${_f(l.partyPending)}",
                                  align: pw.TextAlign.right,
                                  bold: true,
                                  col: const PdfColor(0.0, 0.4, 0.0))
                            ]),
                        if (l.paymentReceived > 0)
                          pw.TableRow(children: [
                            _cell("", align: pw.TextAlign.center),
                            _cell("Less: Advance Received"),
                            _cell("(${_f(l.paymentReceived)})",
                                align: pw.TextAlign.right)
                          ]),
                        pw.TableRow(
                            decoration: const pw.BoxDecoration(
                                color: PdfColor(0.88, 0.97, 0.88)),
                            children: [
                              _cell("", align: pw.TextAlign.center),
                              _cell("NET AMOUNT DUE", bold: true),
                              _cell("â‚¹ ${_f(l.partyPending)}",
                                  align: pw.TextAlign.right,
                                  bold: true,
                                  col: const PdfColor(0.0, 0.4, 0.0))
                            ]),
                      ]),
                  if (up.bankAccount.isNotEmpty) ...[
                    pw.SizedBox(height: 10),
                    pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                            color: const PdfColor(0.97, 0.97, 0.97),
                            borderRadius: pw.BorderRadius.circular(4)),
                        child: pw.Row(children: [
                          pw.Text("Bank: ",
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, fontSize: 9)),
                          pw.Text(up.bankName,
                              style: const pw.TextStyle(fontSize: 9)),
                          pw.SizedBox(width: 16),
                          pw.Text("A/c: ",
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, fontSize: 9)),
                          pw.Text(up.bankAccount,
                              style: const pw.TextStyle(fontSize: 9)),
                          pw.SizedBox(width: 16),
                          pw.Text("IFSC: ",
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, fontSize: 9)),
                          pw.Text(up.bankIfsc,
                              style: const pw.TextStyle(fontSize: 9))
                        ]))
                  ],
                  if (l.lrNotes.isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Text("Notes: ${l.lrNotes}",
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColor(0.4, 0.4, 0.4)))
                  ],
                  pw.Spacer(),
                  pw.Divider(thickness: 0.8),
                  pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text("Declaration:",
                                  style: pw.TextStyle(
                                      fontSize: 8,
                                      fontWeight: pw.FontWeight.bold)),
                              pw.Text(
                                  "This invoice shows the actual price of services described.",
                                  style: const pw.TextStyle(
                                      fontSize: 7.5,
                                      color: PdfColor(0.4, 0.4, 0.4)))
                            ]),
                        pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Container(
                                  width: 140,
                                  height: 1,
                                  color: const PdfColor(0.3, 0.3, 0.3)),
                              pw.SizedBox(height: 4),
                              pw.Text("Authorised Signatory",
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                              pw.Text(up.companyName,
                                  style: const pw.TextStyle(
                                      fontSize: 8,
                                      color: PdfColor(0.4, 0.4, 0.4)))
                            ]),
                      ]),
                ])));
    try {
      await Printing.sharePdf(
          bytes: await pdf.save(),
          filename: 'Invoice_INV-${l.id}_${l.partyName}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("PDF Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _addEntry() {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = "Payment Received";
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (c) => StatefulBuilder(
            builder: (ctx, setS) => Container(
                  decoration: const BoxDecoration(
                      color: Color(0xFFFBF7F0),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24))),
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom,
                      left: 24,
                      right: 24,
                      top: 28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text("Add to Ledger â€” ${_l.partyName}",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        initialValue: type,
                        decoration: InputDecoration(
                            labelText: "Entry Type",
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00), width: 2))),
                        items: [
                          "Payment Received",
                          "Penalty Deducted",
                          "TDS Deducted",
                          "Short Landing Claim",
                          "Other Deduction"
                        ]
                            .map((t) =>
                                DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) => setS(() => type = v!)),
                    const SizedBox(height: 12),
                    TextField(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        controller: amtCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: "Amount (â‚¹)",
                            prefixIcon: const Icon(Icons.currency_rupee),
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00),
                                    width: 2)))),
                    const SizedBox(height: 12),
                    TextField(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        controller: noteCtrl,
                        decoration: InputDecoration(
                            labelText: "Notes / Reference",
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00),
                                    width: 2)))),
                    const SizedBox(height: 18),
                    SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF8E1),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: () {
                              double amt = double.tryParse(amtCtrl.text) ?? 0;
                              if (amt <= 0) return;
                              final upd = TripLedger(
                                  id: _l.id,
                                  date: _l.date,
                                  partyName: _l.partyName,
                                  vehicleNo: _l.vehicleNo,
                                  route: _l.route,
                                  ownership: _l.ownership,
                                  eWayBillNo: _l.eWayBillNo,
                                  materialName: _l.materialName,
                                  loadingPoint: _l.loadingPoint,
                                  unloadingPoint: _l.unloadingPoint,
                                  loadingState: _l.loadingState,
                                  unloadingState: _l.unloadingState,
                                  consignorPhone: _l.consignorPhone,
                                  consignorEmail: _l.consignorEmail,
                                  consignorGstin: _l.consignorGstin,
                                  freightBilled: _l.freightBilled,
                                  paymentReceived: type == "Payment Received"
                                      ? _l.paymentReceived + amt
                                      : _l.paymentReceived,
                                  diesel: _l.diesel,
                                  toll: _l.toll,
                                  driverExp: _l.driverExp,
                                  materialLoss: type == "Short Landing Claim"
                                      ? _l.materialLoss + amt
                                      : _l.materialLoss,
                                  marketTruckFreight: _l.marketTruckFreight,
                                  marketAdvancePaid: _l.marketAdvancePaid,
                                  penalties: (type == "Penalty Deducted" ||
                                          type == "Other Deduction")
                                      ? _l.penalties + amt
                                      : _l.penalties,
                                  tdsDeduction: type == "TDS Deducted"
                                      ? _l.tdsDeduction + amt
                                      : _l.tdsDeduction,
                                  distanceKm: _l.distanceKm,
                                  fuelEconomy: _l.fuelEconomy,
                                  driverName: _l.driverName,
                                  paymentTermsDays: _l.paymentTermsDays,
                                  lrNotes: _l.lrNotes.isNotEmpty
                                      ? "${_l.lrNotes}\n$type: â‚¹${amt.toStringAsFixed(0)} â€” ${noteCtrl.text}"
                                      : "$type: â‚¹${amt.toStringAsFixed(0)} â€” ${noteCtrl.text}",
                                  gstType: _l.gstType,
                                  gstRate: _l.gstRate,
                                  isGstInclusive: _l.isGstInclusive,
                                  weightTons: _l.weightTons,
                                  weightUnit: _l.weightUnit);
                              setState(() => _l = upd);
                              widget.onUpdateLedger(upd);
                              Navigator.pop(c);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                  content: Text(
                                      "âœ… $type of â‚¹${amt.toStringAsFixed(0)} recorded")));
                            },
                            child: const Text("Save Entry",
                                style: TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)))),
                    const SizedBox(height: 24),
                  ]),
                )));
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final isSelf = l.ownership == VehicleOwnership.self;
    final sc = l.isPaymentOverdue
        ? Colors.red
        : l.isDueSoon
            ? Colors.orange
            : l.partyPending <= 0
                ? Colors.green
                : Colors.orange;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
          backgroundColor: const Color(0xFFFFF8E1),
          iconTheme: const IconThemeData(color: Color(0xFF000000)),
          title: Text(l.partyName,
              style: const TextStyle(
                  color: Color(0xFF000000),
                  fontWeight: FontWeight.w900,
                  fontSize: 16)),
          actions: [
            IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: Color(0xFF000000)),
                tooltip: "Add Entry",
                onPressed: _addEntry)
          ]),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(l.date,
                    style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                Chip(
                    label: Text(isSelf ? "SELF FLEET" : "MARKET TRUCK",
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF000000))),
                    backgroundColor: isSelf ? Colors.blueAccent : Colors.purple,
                    padding: const EdgeInsets.symmetric(horizontal: 4))
              ]),
              const SizedBox(height: 8),
              Text(l.partyName,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF000000))),
              Text(l.vehicleNo,
                  style: const TextStyle(
                      fontSize: 14,
                      color: Colors.indigo,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Column(children: [
                    _ir(Icons.route, "Route", l.route),
                    if (l.loadingPoint.isNotEmpty)
                      _ir(Icons.trip_origin, "Loading",
                          "${l.loadingPoint}${l.loadingState.isNotEmpty ? ', ${l.loadingState}' : ''}"),
                    if (l.unloadingPoint.isNotEmpty)
                      _ir(Icons.location_on, "Unloading",
                          "${l.unloadingPoint}${l.unloadingState.isNotEmpty ? ', ${l.unloadingState}' : ''}"),
                    _ir(Icons.science, "Material", l.materialName),
                    if (l.weightTons > 0)
                      _ir(Icons.scale, "Weight",
                          "${l.weightTons} ${l.weightUnit}"),
                    _ir(Icons.receipt, "E-Way Bill", l.eWayBillNo),
                    if (l.platformCommission > 0)
                      _ir(Icons.percent, "Platform Fee (your 2%)",
                          "-â‚¹${l.platformCommission.toStringAsFixed(0)}",
                          col: Colors.red.shade700),
                    if (l.consignorCommission > 0)
                      _ir(Icons.percent, "Consignor Fee (2%)",
                          "â‚¹${l.consignorCommission.toStringAsFixed(0)}",
                          col: Colors.orange.shade700),
                    if (l.driverName != null)
                      _ir(Icons.person, "Driver", l.driverName!),
                    if (l.distanceKm > 0)
                      _ir(Icons.map, "Distance",
                          "${l.distanceKm.toStringAsFixed(0)} km"),
                  ])),
              const SizedBox(height: 14),
              // â”€â”€ DOCUMENTS â”€â”€
              const Text("DOCUMENTS",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _aBtn(Icons.picture_as_pdf, "Lorry Receipt (LR)",
                        const Color(0xFFFFF8E1), _shareLR)),
                const SizedBox(width: 8),
                Expanded(
                    child: _aBtn(Icons.receipt_long, "Tax Invoice",
                        Colors.indigo, _shareInvoice)),
              ]),
              const SizedBox(height: 8),
              // Share All Documents in one tap
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F9D58),
                        foregroundColor: const Color(0xFFFFF8E1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: _shareAllDocs,
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text("Share All Documents with Consignor",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  )),
              const SizedBox(height: 12),
              const Text("ACTIONS",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _aBtn(Icons.add_circle, "Add Entry", Colors.green,
                        _addEntry)),
                const SizedBox(width: 8),
                Expanded(
                    child: _aBtn(
                        Icons.gps_fixed_rounded, "Track Live", Colors.teal, () {
                  if (!widget.subscription.canUseGPS) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("GPS Tracking requires PRO plan"),
                        backgroundColor: Colors.orange));
                    return;
                  }
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => LiveTrackingScreen(
                              route: l.route,
                              vehicleNo: l.vehicleNo,
                              distanceKm: l.distanceKm)));
                }))
              ]),
            ])),
            const SizedBox(height: 16),
            _card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("FINANCIAL BREAKDOWN",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey,
                        letterSpacing: 1.2)),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: sc.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(
                        l.partyPending <= 0
                            ? "SETTLED"
                            : l.isPaymentOverdue
                                ? "OVERDUE"
                                : l.isDueSoon
                                    ? "DUE SOON"
                                    : "OUTSTANDING",
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: sc))),
              ]),
              const SizedBox(height: 14),
              _fr("Freight Billed", l.freightBilled, b: true),
              if (l.gstAmount > 0)
                _fr(
                    l.gstType == GstType.igst
                        ? "IGST @${l.gstRate}%"
                        : "GST @${l.gstRate}%",
                    l.gstAmount,
                    c: Colors.indigo),
              _fr("Advance Received", l.paymentReceived, c: Colors.green),
              const Divider(height: 16),
              if (isSelf) ...[
                _fr("Diesel Fuel", l.diesel, c: Colors.deepOrange),
                _fr("Toll / FASTag", l.toll, c: Colors.orange),
                _fr("Driver Expenses", l.driverExp, c: Colors.purple),
                if (l.materialLoss > 0)
                  _fr("Material Loss", l.materialLoss, c: Colors.red[900]!)
              ] else ...[
                _fr("Market Truck Freight", l.marketTruckFreight,
                    c: Colors.red),
                _fr("Advance Paid to Market", l.marketAdvancePaid,
                    c: Colors.red)
              ],
              if (l.tdsDeduction > 0)
                _fr("TDS Deducted", l.tdsDeduction, c: Colors.brown),
              if (l.penalties > 0)
                _fr("Penalties / Deductions", l.penalties,
                    c: Colors.deepOrange),
              const Divider(height: 16),
              if (l.partyPending > 0)
                Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: sc.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              l.isPaymentOverdue
                                  ? "OVERDUE BALANCE"
                                  : l.isDueSoon
                                      ? "DUE SOON"
                                      : "PENDING BALANCE",
                              style: TextStyle(
                                  color: sc,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13)),
                          Text("â‚¹${l.partyPending.toStringAsFixed(0)}",
                              style: TextStyle(
                                  color: sc,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22))
                        ])),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(isSelf ? "NET PROFIT" : "NET COMMISSION",
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF000000))),
                Text("â‚¹${l.tripProfit.toStringAsFixed(0)}",
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.blueAccent))
              ]),
              if (l.paymentDueDate != null) ...[
                const SizedBox(height: 10),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.calendar_today,
                          size: 12, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                          "Payment due: ${l.paymentDueDate!.day}/${l.paymentDueDate!.month}/${l.paymentDueDate!.year}",
                          style: TextStyle(
                              fontSize: 11,
                              color: l.isPaymentOverdue
                                  ? Colors.red
                                  : l.isDueSoon
                                      ? Colors.orange
                                      : Colors.grey,
                              fontWeight: FontWeight.w600))
                    ]))
              ],
            ])),
          ])),
    );
  }

  Widget _card(Widget child) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)
          ]),
      child: child);
  Future<void> _shareAllDocs() async {
    if (!widget.subscription.canExportPDF) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          content: Text("PDF Export requires PRO plan or above")));
      return;
    }
    final l = _l;
    // Build both PDFs
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.indigo,
        behavior: SnackBarBehavior.floating,
        content: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF000000))),
          SizedBox(width: 12),
          Text("Preparing documents...")
        ])));
    try {
      // Generate LR PDF
      await _shareLR();
      // Small delay then show success
      await Future.delayed(const Duration(milliseconds: 500));
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content:
            Text("Documents shared! LR No: LR-${l.id} | Invoice: INV-${l.id}"),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text("Error: $e")));
    }
  }

  Widget _aBtn(IconData icon, String label, Color c, VoidCallback onTap) =>
      ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: c,
              foregroundColor: const Color(0xFFFFF8E1),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          onPressed: onTap,
          icon: Icon(icon, size: 15),
          label: Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)));
  Widget _ir(IconData icon, String label, String val, {Color? col}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
            width: 80,
            child: Text("$label: ",
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w600))),
        Expanded(
            child: Text(val,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: col ?? const Color(0xFFFFF8E1))))
      ]));
  Widget _fr(String label, double val,
          {Color c = Colors.black87, bool b = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label,
                style: TextStyle(
                    fontWeight: b ? FontWeight.w900 : FontWeight.w600,
                    fontSize: b ? 14 : 13,
                    color: const Color(0xFF000000))),
            Text("â‚¹${val.toStringAsFixed(0)}",
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: c,
                    fontSize: b ? 14 : 13))
          ]));
}

// ================================================================
// TALLY EXPORT SCREEN
// ================================================================
class TallyExportScreen extends StatefulWidget {
  final List<TripLedger> ledgers;
  final List<Driver> drivers;
  final UserProfile userProfile;
  const TallyExportScreen(
      {super.key,
      required this.ledgers,
      required this.drivers,
      required this.userProfile});
  @override
  State<TallyExportScreen> createState() => _TallyExportScreenState();
}

class _TallyExportScreenState extends State<TallyExportScreen> {
  String _fmt = "CA Audit CSV";
  String? _data;

  String _csv() {
    final sb = StringBuffer();
    sb.writeln(
        "Trip ID,Date,Party,Vehicle,Route,Material,E-Way,Loading,Unloading,Freight Billed,Received,Pending,Diesel,Toll,Driver Exp,Shortfall,Penalties,TDS,Market Freight,Profit,GST Type,GST Amt,Weight,Terms,Driver,Status");
    for (final l in widget.ledgers) {
      final st = l.partyPending <= 0
          ? "Cleared"
          : l.isPaymentOverdue
              ? "OVERDUE"
              : l.isDueSoon
                  ? "DUE SOON"
                  : "Pending";
      sb.writeln([
        l.id,
        l.date,
        '"${l.partyName}"',
        l.vehicleNo,
        '"${l.route}"',
        '"${l.materialName}"',
        l.eWayBillNo,
        '"${l.loadingPoint}"',
        '"${l.unloadingPoint}"',
        l.freightBilled.toStringAsFixed(2),
        l.paymentReceived.toStringAsFixed(2),
        l.partyPending.toStringAsFixed(2),
        l.diesel.toStringAsFixed(2),
        l.toll.toStringAsFixed(2),
        l.driverExp.toStringAsFixed(2),
        l.materialLoss.toStringAsFixed(2),
        l.penalties.toStringAsFixed(2),
        l.tdsDeduction.toStringAsFixed(2),
        l.marketTruckFreight.toStringAsFixed(2),
        l.tripProfit.toStringAsFixed(2),
        l.gstType.name,
        l.gstAmount.toStringAsFixed(2),
        "${l.weightTons} ${l.weightUnit}",
        l.paymentTermsDays,
        l.driverName ?? '',
        st
      ].join(','));
    }
    return sb.toString();
  }

  String _tallyXml() {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln(
        '<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY><IMPORTDATA><REQUESTDESC>');
    sb.writeln(
        '<REPORTNAME>Vouchers</REPORTNAME><STATICVARIABLES><SVCURRENTCOMPANY>${widget.userProfile.companyName}</SVCURRENTCOMPANY></STATICVARIABLES>');
    sb.writeln('</REQUESTDESC><REQUESTDATA>');
    for (final l in widget.ledgers) {
      sb.writeln(
          '<TALLYMESSAGE><VOUCHER VCHTYPE="Sales" ACTION="Create"><DATE>${l.date.replaceAll("/", "")}</DATE><NARRATION>Freight-${l.materialName}-${l.route}-EWB:${l.eWayBillNo}</NARRATION><VOUCHERTYPENAME>Sales</VOUCHERTYPENAME><PARTYLEDGERNAME>${l.partyName}</PARTYLEDGERNAME><ALLLEDGERENTRIES.LIST><LEDGERNAME>${l.partyName}</LEDGERNAME><ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE><AMOUNT>-${l.freightBilled.toStringAsFixed(2)}</AMOUNT></ALLLEDGERENTRIES.LIST><ALLLEDGERENTRIES.LIST><LEDGERNAME>Freight Income</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>${l.freightBilled.toStringAsFixed(2)}</AMOUNT></ALLLEDGERENTRIES.LIST></VOUCHER></TALLYMESSAGE>');
    }
    sb.writeln('</REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>');
    return sb.toString();
  }

  String _aging() {
    final m = <String, double>{};
    for (final l in widget.ledgers) {
      m[l.partyName] = (m[l.partyName] ?? 0) + l.partyPending;
    }
    final sb = StringBuffer();
    sb.writeln("Party Aging Report â€” ${widget.userProfile.companyName}");
    sb.writeln(
        "Generated: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}\n---");
    sb.writeln("Party Name,Outstanding,Overdue Trips");
    for (final e in m.entries) {
      final ov = widget.ledgers
          .where((l) => l.partyName == e.key && l.isPaymentOverdue)
          .length;
      sb.writeln('"${e.key}",${e.value.toStringAsFixed(2)},$ov');
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: const Color(0xFFFFF8E1),
            iconTheme: const IconThemeData(color: Color(0xFF000000)),
            title: const Text("Tally / CA Export",
                style: TextStyle(
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.w900))),
        body: Column(children: [
          Container(
              color: const Color(0xFF000000),
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Export Format",
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Color(0xFF000000))),
                    const SizedBox(height: 10),
                    ...[
                      "CA Audit CSV",
                      "Tally XML",
                      "Party Aging Report"
                    ].map((f) => RadioListTile<String>(
                        title: Text(f,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            f == "CA Audit CSV"
                                ? "Full ledger with GST, TDS, deductions"
                                : f == "Tally XML"
                                    ? "Import into TallyPrime/ERP9"
                                    : "Outstanding by party for collections",
                            style: const TextStyle(fontSize: 11)),
                        value: f,
                        groupValue: _fmt,
                        activeColor: const Color(0xFFFFF8E1),
                        onChanged: (v) => setState(() => _fmt = v!))),
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF8E1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(double.infinity, 0)),
                        onPressed: () =>
                            setState(() => _data = _fmt == "CA Audit CSV"
                                ? _csv()
                                : _fmt == "Tally XML"
                                    ? _tallyXml()
                                    : _aging()),
                        icon: const Icon(Icons.auto_awesome,
                            color: Color(0xFF000000), size: 16),
                        label: Text("Generate $_fmt",
                            style: const TextStyle(
                                color: Color(0xFF000000),
                                fontWeight: FontWeight.bold))),
                    if (_data != null) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Color(0xFF000000)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12)),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: _data!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text("âœ… Copied to clipboard"),
                                          backgroundColor: Colors.green,
                                          behavior: SnackBarBehavior.floating));
                                },
                                icon: const Icon(Icons.copy,
                                    color: Color(0xFF000000), size: 16),
                                label: const Text("Copy",
                                    style: TextStyle(
                                        color: Color(0xFF000000),
                                        fontWeight: FontWeight.bold)))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12)),
                                onPressed: () async {
                                  final ext =
                                      _fmt == "Tally XML" ? "xml" : "csv";
                                  final fname =
                                      "${_fmt.replaceAll(' ', '_')}_${DateTime.now().day}${DateTime.now().month}${DateTime.now().year}.$ext";
                                  final dir = await getTemporaryDirectory();
                                  final file = File('${dir.path}/$fname');
                                  await file.writeAsString(_data!);
                                  await Share.shareXFiles([XFile(file.path)],
                                      subject: _fmt,
                                      text:
                                          "Route Master ERP Export â€” ${widget.userProfile.companyName}");
                                },
                                icon: const Icon(Icons.share,
                                    color: Color(0xFF000000), size: 16),
                                label: const Text("Share File",
                                    style: TextStyle(
                                        color: Color(0xFF000000),
                                        fontWeight: FontWeight.bold)))),
                      ]),
                    ],
                  ])),
          if (_data != null)
            Expanded(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFB8C00),
                            borderRadius: BorderRadius.circular(12)),
                        child: SelectableText(_data!,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Color(0xFFFB8C00),
                                height: 1.5))))),
        ]),
      );
}

// ================================================================
// BANK IMPORT SCREEN
// ================================================================
class BankImportScreen extends StatefulWidget {
  final List<TripLedger> ledgers;
  final Function(String, double) onMatch;
  const BankImportScreen(
      {super.key, required this.ledgers, required this.onMatch});
  @override
  State<BankImportScreen> createState() => _BankImportScreenState();
}

class _BankImportScreenState extends State<BankImportScreen> {
  List<BankEntry> _entries = [];
  bool _parsed = false;
  final _ctrl = TextEditingController();

  void _parse(String raw) {
    final lines = raw.trim().split('\n');
    final out = <BankEntry>[];
    for (int i = 1; i < lines.length; i++) {
      final cols = lines[i].split(',');
      if (cols.length < 4) continue;
      try {
        final e = BankEntry(
            date: cols[0].trim().replaceAll('"', ''),
            narration:
                cols.length > 1 ? cols[1].trim().replaceAll('"', '') : '',
            refNo: cols.length > 2 ? cols[2].trim().replaceAll('"', '') : '',
            debit: double.tryParse(cols.length > 3
                    ? cols[3].trim().replaceAll('"', '').replaceAll(',', '')
                    : '0') ??
                0,
            credit: double.tryParse(cols.length > 4
                    ? cols[4].trim().replaceAll('"', '').replaceAll(',', '')
                    : '0') ??
                0);
        if (e.credit > 0 || e.debit > 0) out.add(e);
      } catch (_) {}
    }
    for (final e in out) {
      for (final l in widget.ledgers) {
        final n = e.narration.toLowerCase();
        final p = l.partyName.toLowerCase();
        if (n.contains(p) ||
            p.split(' ').any((w) => w.length > 3 && n.contains(w))) {
          e.isMatched = true;
          e.matchedLedgerId = l.id;
          break;
        }
      }
    }
    setState(() {
      _entries = out;
      _parsed = true;
    });
  }

  void _applyAll() {
    int n = 0;
    for (final e in _entries) {
      if (e.isMatched && e.matchedLedgerId != null && e.credit > 0) {
        widget.onMatch(e.matchedLedgerId!, e.credit);
        n++;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        content: Text("âœ… $n entries applied to ledgers")));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final matched =
        _entries.where((e) => (e).isMatched == true).length;
    return Scaffold(
      appBar: AppBar(
          backgroundColor: const Color(0xFFFFF8E1),
          iconTheme: const IconThemeData(color: Color(0xFF000000)),
          title: const Text("Bank Statement Import",
              style: TextStyle(
                  color: Color(0xFF000000), fontWeight: FontWeight.w900)),
          actions: [
            if (matched > 0)
              TextButton(
                  onPressed: _applyAll,
                  child: Text("Apply $matched",
                      style: const TextStyle(
                          color: Color(0xFFFB8C00),
                          fontWeight: FontWeight.bold)))
          ]),
      body: Column(children: [
        Container(
            color: const Color(0xFF000000),
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Paste Bank CSV",
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xFF000000))),
              const SizedBox(height: 4),
              const Text("Format: Date, Narration, Ref No, Debit, Credit",
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                  controller: _ctrl,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                      hintText:
                          "Date,Narration,RefNo,Debit,Credit\n23/04/2026,NEFT FROM RELIANCE,REF123,,185000",
                      hintStyle:
                          TextStyle(fontSize: 10, color: Colors.grey[400]),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50])),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF8E1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 20)),
                  onPressed: () => _parse(_ctrl.text),
                  icon: const Icon(Icons.auto_fix_high,
                      color: Color(0xFF000000)),
                  label: const Text("Parse & Auto-Match",
                      style: TextStyle(
                          color: Color(0xFF000000),
                          fontWeight: FontWeight.bold))),
            ])),
        if (_parsed)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${_entries.length} entries",
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.grey)),
                    Text("$matched matched",
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: matched > 0 ? Colors.green : Colors.grey))
                  ])),
        Expanded(
            child: _entries.isEmpty
                ? const Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Icon(Icons.file_upload_outlined,
                            size: 60, color: Colors.grey),
                        SizedBox(height: 12),
                        Text("Paste CSV and tap Parse",
                            style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 16))
                      ]))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _entries.length,
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      final ml = e.matchedLedgerId != null
                          ? widget.ledgers
                              .where((l) => l.id == e.matchedLedgerId)
                              .firstOrNull
                          : null;
                      return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: const Color(0xFF000000),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: e.isMatched
                                      ? Colors.green.shade200
                                      : Colors.grey.shade200)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(e.narration,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13),
                                                overflow:
                                                    TextOverflow.ellipsis),
                                            Text(e.date,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey))
                                          ])),
                                      Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            if (e.credit > 0)
                                              Text(
                                                  "+â‚¹${e.credit.toStringAsFixed(0)}",
                                                  style: const TextStyle(
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 14)),
                                            if (e.debit > 0)
                                              Text(
                                                  "-â‚¹${e.debit.toStringAsFixed(0)}",
                                                  style: const TextStyle(
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 13))
                                          ]),
                                    ]),
                                if (ml != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.08),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                                child: Row(children: [
                                              const Icon(Icons.check_circle,
                                                  size: 14,
                                                  color: Colors.green),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                  child: Text(
                                                      "${ml.partyName} â€” â‚¹${ml.partyPending.toStringAsFixed(0)} pending",
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.green,
                                                          fontWeight:
                                                              FontWeight.w600)))
                                            ])),
                                            if (e.credit > 0)
                                              TextButton(
                                                  onPressed: () {
                                                    widget.onMatch(
                                                        e.matchedLedgerId!,
                                                        e.credit);
                                                    setState(() =>
                                                        e.isMatched = true);
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(SnackBar(
                                                            backgroundColor:
                                                                Colors.green,
                                                            behavior:
                                                                SnackBarBehavior
                                                                    .floating,
                                                            content: Text(
                                                                "âœ… â‚¹${e.credit.toStringAsFixed(0)} applied")));
                                                  },
                                                  style: TextButton.styleFrom(
                                                      foregroundColor:
                                                          Colors.green,
                                                      padding: EdgeInsets.zero,
                                                      minimumSize:
                                                          const Size(60, 28)),
                                                  child: const Text("Apply",
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 12))),
                                          ]))
                                ],
                              ]));
                    })),
      ]),
    );
  }
}

// ================================================================
// ADVANCED ADMIN SCREEN (hidden â€” accessed via 7-tap title only)
// ================================================================

// ================================================================
// DRIVER LOCATION SHARING â€” phone GPS like Uber/Zomato
// ================================================================
class DriverTrackingMode extends StatefulWidget {
  final String tripId, vehicleNo, route;
  const DriverTrackingMode(
      {super.key,
      required this.tripId,
      required this.vehicleNo,
      required this.route});
  @override
  State<DriverTrackingMode> createState() => _DriverTrackingModeState();
}

class _DriverTrackingModeState extends State<DriverTrackingMode> {
  bool _sharing = false;
  Timer? _locTimer;
  String _status = "Not sharing";
  double? _lat, _lng;
  double _speed = 0;

  Future<void> _startSharing() async {
    setState(() {
      _sharing = true;
      _status = "Getting location...";
    });
    // Simulate driver GPS â€” in production uses geolocator package
    // Real implementation: Position pos = await Geolocator.getCurrentPosition()
    _simulateLocation();
    _locTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _simulateLocation());
  }

  void _simulateLocation() {
    // Demo: simulate moving along route
    // Real: get phone GPS and push to Firestore
    setState(() {
      _lat = 23.0225 + (math.Random().nextDouble() - 0.5) * 0.001;
      _lng = 72.5714 + (math.Random().nextDouble() - 0.5) * 0.001;
      _speed = 45 + math.Random().nextDouble() * 20;
      _status =
          "Sharing live â€¢ ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";
    });
    // Push to Firebase Firestore â€” fleet owner reads this
    try {
      FirebaseFirestore.instance
          .collection('live_locations')
          .doc(widget.tripId)
          .set({
        'lat': _lat,
        'lng': _lng,
        'speed': _speed,
        'vehicleNo': widget.vehicleNo,
        'route': widget.route,
        'updatedAt': FieldValue.serverTimestamp(),
        'sharing': true,
      });
    } catch (_) {}
  }

  Future<void> _stopSharing() async {
    _locTimer?.cancel();
    try {
      await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(widget.tripId)
          .update({'sharing': false});
    } catch (_) {}
    setState(() {
      _sharing = false;
      _status = "Stopped sharing";
    });
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFFF8E1),
        appBar: AppBar(
            backgroundColor: const Color(0xFFFFF8E1),
            iconTheme: const IconThemeData(color: Color(0xFF000000)),
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Driver Mode",
                  style: TextStyle(
                      color: Color(0xFF000000),
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
              Text(widget.vehicleNo,
                  style:
                      const TextStyle(color: Color(0x541A3A2A), fontSize: 11)),
            ])),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            // Status card
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: _sharing
                          ? [const Color(0xFF064E3B), const Color(0xFF065F46)]
                          : [const Color(0xFFFB8C00), const Color(0xFFFFF8E1)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(children: [
                  Icon(
                      _sharing
                          ? Icons.gps_fixed_rounded
                          : Icons.gps_not_fixed_rounded,
                      color: _sharing
                          ? const Color(0xFFFB8C00)
                          : Color(0x381A3A2A),
                      size: 48),
                  const SizedBox(height: 12),
                  Text(
                      _sharing
                          ? "SHARING LIVE LOCATION"
                          : "LOCATION SHARING OFF",
                      style: TextStyle(
                          color: _sharing
                              ? const Color(0xFFFB8C00)
                              : Color(0x381A3A2A),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Text(_status,
                      style: const TextStyle(
                          color: Color(0x541A3A2A), fontSize: 12)),
                  if (_lat != null) ...[
                    const SizedBox(height: 8),
                    Text(
                        "${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}",
                        style: const TextStyle(
                            color: Color(0x381A3A2A),
                            fontSize: 10,
                            fontFamily: 'monospace')),
                    Text("Speed: ${_speed.toStringAsFixed(0)} km/h",
                        style: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ])),
            const SizedBox(height: 16),
            Text("Route: ${widget.route}",
                style: const TextStyle(color: Color(0x541A3A2A), fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const Spacer(),
            // Main action button
            SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _sharing ? Colors.red.shade800 : Colors.green.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: _sharing ? _stopSharing : _startSharing,
                  icon: Icon(
                      _sharing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      size: 24),
                  label: Text(
                      _sharing
                          ? "Stop Sharing Location"
                          : "Start Sharing Location",
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF000000))),
                )),
            const SizedBox(height: 12),
            const Text("Fleet owner sees your live position on their screen",
                style: TextStyle(color: Color(0x241A3A2A), fontSize: 11),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

// ================================================================
// ADMIN DASHBOARD â€” Full Control Panel
// ================================================================
class AdvancedAdminScreen extends StatefulWidget {
  final List<TripLedger> ledgers;
  final List<Asset> fleet;
  final List<Driver> drivers;
  final List<KredXApplication> kredxApps;
  final UserProfile userProfile;
  final SubscriptionInfo subscription;
  final VoidCallback onFactoryReset;
  final VoidCallback onUpdate;
  const AdvancedAdminScreen(
      {super.key,
      required this.ledgers,
      required this.fleet,
      required this.drivers,
      required this.kredxApps,
      required this.userProfile,
      required this.subscription,
      required this.onFactoryReset,
      required this.onUpdate});
  @override
  State<AdvancedAdminScreen> createState() => _AdvancedAdminScreenState();
}

class _AdvancedAdminScreenState extends State<AdvancedAdminScreen>
    with TickerProviderStateMixin {
  late TabController _tabs;
  int _selectedTab = 0;
  String _searchQuery = '';

  // Admin-editable state
  late List<KredXApplication> _kredx;
  late SubscriptionTier _subTier;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() => _selectedTab = _tabs.index);
    });
    _kredx = widget.kredxApps;
    _subTier = widget.subscription.tier;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // â”€â”€ Helpers â”€â”€
  String _f(double v) => v >= 10000000
      ? 'â‚¹${(v / 10000000).toStringAsFixed(1)}Cr'
      : v >= 100000
          ? 'â‚¹${(v / 100000).toStringAsFixed(1)}L'
          : v >= 1000
              ? 'â‚¹${(v / 1000).toStringAsFixed(1)}K'
              : 'â‚¹${v.toStringAsFixed(0)}';
  String _pct(double a, double b) =>
      b > 0 ? '${(a / b * 100).toStringAsFixed(1)}%' : '0%';

  // â”€â”€ Metrics â”€â”€
  double get _rev => widget.ledgers.fold(0.0, (s, l) => s + l.freightBilled);
  double get _profit => widget.ledgers.fold(0.0, (s, l) => s + l.tripProfit);
  double get _pending => widget.ledgers
      .fold(0.0, (s, l) => s + (l.partyPending > 0 ? l.partyPending : 0));
  double get _commissions => widget.ledgers
      .fold(0.0, (s, l) => s + l.platformCommission + l.consignorCommission);
  double get _diesel => widget.ledgers.fold(0.0, (s, l) => s + l.diesel);
  double get _toll => widget.ledgers.fold(0.0, (s, l) => s + l.toll);
  double get _drvExp => widget.ledgers.fold(0.0, (s, l) => s + l.driverExp);
  int get _overdueCount => widget.ledgers
      .where((l) => l.isPaymentOverdue && l.partyPending > 0)
      .length;
  int get _settledCount =>
      widget.ledgers.where((l) => l.partyPending <= 0).length;
  List<MapEntry<String, double>> get _topParties {
    final m = <String, double>{};
    for (final l in widget.ledgers) {
      m[l.partyName] = (m[l.partyName] ?? 0) + l.freightBilled;
    }
    return (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .toList();
  }

  List<MapEntry<String, double>> get _topVehicles {
    final m = <String, double>{};
    for (final l in widget.ledgers) {
      m[l.vehicleNo] = (m[l.vehicleNo] ?? 0) + l.freightBilled;
    }
    return (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .toList();
  }

  // â”€â”€ Shared Widgets â”€â”€
  static const _bg = Color(0xFFFFF8E1);
  static const _card = Color(0xFFFFF8E1);
  static const _card2 = Color(0xFFFFF8E1);
  static const _border = Color(0xFFFB8C00);
  static const _accent = Color(0xFFFB8C00);
  static const _green = Color(0xFFFB8C00);
  static const _red = Color(0xFFE53E3E);
  static const _amber = Color(0xFFFB8C00);
  static const _purple = Color(0xFF5C3D2E);
  static const _cyan = Color(0xFFFB8C00);
  static const _pink = Color(0xFFE85D3D);

  Widget _sectionTitle(String t, {IconData? icon, Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          if (icon != null)
            Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: (color ?? _accent).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color ?? _accent, size: 14)),
          Text(t,
              style: TextStyle(
                  color: color ?? const Color(0xFFFFF8E1),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
        ]),
      );

  Widget _metricCard(String label, String value, IconData icon, Color color,
          {String? sub, double? trend}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
          gradient: LinearGradient(
              colors: [color.withOpacity(0.08), _card],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color, size: 18)),
                if (trend != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: (trend >= 0 ? _green : _red).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(trend >= 0 ? Icons.trending_up : Icons.trending_down,
                          size: 10, color: trend >= 0 ? _green : _red),
                      const SizedBox(width: 2),
                      Text('${trend.abs().toStringAsFixed(1)}%',
                          style: TextStyle(
                              fontSize: 9,
                              color: trend >= 0 ? _green : _red,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 12),
              Text(value,
                  style: const TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1)),
              const SizedBox(height: 3),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        color: color.withOpacity(0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600))
              ],
            ]),
      );

  Widget _barChart(String label, double value, double max, Color color) {
    final pct = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
          Text(_f(value),
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.toDouble(),
              minHeight: 6,
              backgroundColor: const Color(0xFFFFF8E1).withOpacity(0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            )),
      ]),
    );
  }

  Widget _statusBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.4))),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3)),
      );

  Widget _actionBtn(String label, Color color, VoidCallback onTap,
          {IconData? icon}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              gradient:
                  LinearGradient(colors: [color, color.withOpacity(0.75)]),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, color: const Color(0xFF000000), size: 13),
              const SizedBox(width: 5)
            ],
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ]),
        ),
      );

  // â”€â”€ TAB 1: Overview / Analytics â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _tabOverview() {
    final totalExp = _diesel + _toll + _drvExp;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Revenue hero banner
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [
            Color(0xFFFFF8E1),
            Color(0xFFFB8C00),
            Color(0xFF0EA5E9)
          ], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFFB8C00).withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, 8))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.analytics_rounded, color: Color(0x701C1917), size: 14),
            SizedBox(width: 6),
            Text("PLATFORM OVERVIEW",
                style: TextStyle(
                    color: Color(0x701C1917),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5))
          ]),
          const SizedBox(height: 12),
          Text(_f(_rev),
              style: const TextStyle(
                  color: Color(0xFFFFF8E1),
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -1)),
          const Text("Total Revenue",
              style: TextStyle(color: Color(0x701C1917), fontSize: 13)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child:
                    _revPill("Profit", _f(_profit), const Color(0xFFFB8C00))),
            const SizedBox(width: 10),
            Expanded(
                child: _revPill("Pending", _f(_pending), Colors.orangeAccent)),
            const SizedBox(width: 10),
            Expanded(
                child: _revPill(
                    "Margin", _pct(_profit, _rev), const Color(0xFFFFF8E1))),
          ]),
        ]),
      ),
      // KPI 2Ã—2 grid
      GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            _metricCard("Total Trips", "${widget.ledgers.length}",
                Icons.local_shipping_rounded, _accent,
                sub: "$_settledCount settled"),
            _metricCard("Fleet Size", "${widget.fleet.length}",
                Icons.directions_car_rounded, _green,
                sub:
                    "${widget.fleet.where((a) => a.docs.every((d) => d.isUploaded)).length} compliant"),
            _metricCard("Drivers", "${widget.drivers.length}",
                Icons.badge_rounded, _purple,
                sub:
                    "${widget.drivers.where((d) => d.isVerified).length} verified"),
            _metricCard("Overdue", "$_overdueCount trips",
                Icons.warning_amber_rounded, _red,
                sub: "Needs follow-up"),
          ]),
      const SizedBox(height: 16),
      // Platform commissions
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _green.withOpacity(0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle("PLATFORM REVENUE",
              icon: Icons.currency_rupee_rounded, color: _green),
          Row(children: [
            _commPill(
                "Fleet Fees",
                _f(widget.ledgers
                    .fold<double>(0, (s, l) => s + l.platformCommission)),
                _green),
            const SizedBox(width: 8),
            _commPill(
                "Consignor Fees",
                _f(widget.ledgers
                    .fold<double>(0, (s, l) => s + l.consignorCommission)),
                _cyan),
            const SizedBox(width: 8),
            _commPill("Total Earned", _f(_commissions), _amber),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      // Expense breakdown chart
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle("EXPENSE BREAKDOWN",
              icon: Icons.pie_chart_rounded, color: _amber),
          _barChart("Diesel Fuel", _diesel, _rev, Colors.orange),
          _barChart("Toll / FASTag", _toll, _rev, Colors.blue),
          _barChart("Driver Expenses", _drvExp, _rev, _purple),
          _barChart("Total Expenses", totalExp, _rev, _red),
          _barChart("Net Profit", _profit, _rev, _green),
        ]),
      ),
      const SizedBox(height: 16),
      // Top parties
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle("TOP PARTIES BY REVENUE",
              icon: Icons.business_rounded, color: _cyan),
          ..._topParties.asMap().entries.map((e) {
            final colors = [_accent, _green, _amber, _purple, _cyan];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                        color: colors[e.key].withOpacity(0.15),
                        shape: BoxShape.circle),
                    child: Center(
                        child: Text("${e.key + 1}",
                            style: TextStyle(
                                color: colors[e.key],
                                fontWeight: FontWeight.w900,
                                fontSize: 11)))),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(e.value.key,
                          style: const TextStyle(
                              color: Color(0xFF000000),
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                      Text(
                          "${widget.ledgers.where((l) => l.partyName == e.value.key).length} trips",
                          style: TextStyle(color: colors[e.key], fontSize: 10)),
                    ])),
                Text(_f(e.value.value),
                    style: TextStyle(
                        color: colors[e.key],
                        fontWeight: FontWeight.w900,
                        fontSize: 14)),
              ]),
            );
          }),
        ]),
      ),
      const SizedBox(height: 16),
      // Top vehicles
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle("TOP VEHICLES BY REVENUE",
              icon: Icons.local_shipping_rounded, color: _purple),
          ..._topVehicles.map((e) => _barChart(e.key, e.value, _rev, _purple)),
        ]),
      ),
    ]);
  }

  Widget _revPill(String l, String v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xFF000000).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(v,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w900, fontSize: 14)),
          Text(l, style: const TextStyle(color: Color(0x701A3A2A), fontSize: 9))
        ]),
      );

  Widget _commPill(String l, String v, Color c) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: c.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withOpacity(0.25))),
        child: Column(children: [
          Text(v,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 2),
          Text(l,
              style:
                  const TextStyle(color: Color(0xFF000000), fontSize: 9))
        ]),
      ));

  // â”€â”€ TAB 2: Finance / Ledger Control â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _tabFinance() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        // Overdue payments
        _sectionTitle(
            "OVERDUE PAYMENTS (${widget.ledgers.where((l) => l.isPaymentOverdue && l.partyPending > 0).length})",
            icon: Icons.warning_rounded,
            color: _red),
        ...widget.ledgers
            .where((l) => l.isPaymentOverdue && l.partyPending > 0)
            .map((l) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border(left: BorderSide(color: _red, width: 3))),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(l.partyName,
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                          Text("${l.vehicleNo} â€¢ ${l.date}",
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontSize: 11)),
                        ])),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_f(l.partyPending),
                              style: const TextStyle(
                                  color: Color(0xFFE53E3E),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15)),
                          if (l.paymentDueDate != null)
                            Text(
                                "Due: ${l.paymentDueDate!.day}/${l.paymentDueDate!.month}",
                                style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 10)),
                        ]),
                  ]),
                )),
        const SizedBox(height: 20),
        // KredX panel
        _sectionTitle("KREDX APPLICATIONS",
            icon: Icons.account_balance_rounded, color: _amber),
        ...(_kredx.isEmpty
            ? [
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                        child: Text("No applications",
                            style: TextStyle(color: Color(0xFF000000)))))
              ]
            : _kredx.map((app) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                  child: Text(app.partyName,
                                      style: const TextStyle(
                                          color: Color(0xFF000000),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15),
                                      overflow: TextOverflow.ellipsis)),
                              _statusBadge(app.statusLabel, app.statusColor),
                            ]),
                        const SizedBox(height: 6),
                        Text(
                            "Applied: ${app.appliedDate} â€¢ ${app.tenureDays} days",
                            style: const TextStyle(
                                color: Color(0xFF000000), fontSize: 11)),
                        const SizedBox(height: 10),
                        Row(children: [
                          _infoChip("Invoice", _f(app.invoiceAmount), _cyan),
                          const SizedBox(width: 8),
                          _infoChip(
                              "Requested", _f(app.requestedAmount), _amber),
                          if (app.approvedAmount > 0) ...[
                            const SizedBox(width: 8),
                            _infoChip(
                                "Approved", _f(app.approvedAmount), _green)
                          ],
                        ]),
                        if (app.status == KredXStatus.submitted ||
                            app.status == KredXStatus.underReview) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  app.status = KredXStatus.underReview;
                                });
                                widget.onUpdate();
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        backgroundColor: Colors.orange,
                                        behavior: SnackBarBehavior.floating,
                                        content:
                                            Text("Moved to Under Review")));
                              },
                              child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color:
                                              Colors.orange.withOpacity(0.4))),
                                  child: const Center(
                                      child: Text("Under Review",
                                          style: TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12)))),
                            )),
                            const SizedBox(width: 8),
                            Expanded(
                                child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  app.status = KredXStatus.rejected;
                                });
                                widget.onUpdate();
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    backgroundColor: _red,
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                        "${app.partyName} â€” Application rejected")));
                              },
                              child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                      color: _red.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: _red.withOpacity(0.4))),
                                  child: const Center(
                                      child: Text("Reject",
                                          style: TextStyle(
                                              color: Color(0xFFE53E3E),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12)))),
                            )),
                            const SizedBox(width: 8),
                            Expanded(
                                child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  app.status = KredXStatus.approved;
                                  app.approvedAmount = app.requestedAmount;
                                });
                                widget.onUpdate();
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    backgroundColor: _green,
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                        "âœ… ${app.partyName} â€” â‚¹${app.requestedAmount.toStringAsFixed(0)} approved")));
                              },
                              child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [
                                        _green,
                                        _green.withOpacity(0.7)
                                      ]),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                            color: _green.withOpacity(0.3),
                                            blurRadius: 8)
                                      ]),
                                  child: const Center(
                                      child: Text("Approve âœ“",
                                          style: TextStyle(
                                              color: Color(0xFF000000),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12)))),
                            )),
                          ]),
                        ],
                        if (app.status == KredXStatus.approved) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                app.status = KredXStatus.disbursed;
                              });
                              widget.onUpdate();
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  backgroundColor: Colors.teal,
                                  behavior: SnackBarBehavior.floating,
                                  content: Text(
                                      "ðŸ’¸ ${app.partyName} â€” â‚¹${app.approvedAmount.toStringAsFixed(0)} disbursed")));
                            },
                            child: Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [
                                      Colors.teal,
                                      Color(0xFF0D9488)
                                    ]),
                                    borderRadius: BorderRadius.circular(10)),
                                child: const Center(
                                    child: Text("Disburse Funds ðŸ’¸",
                                        style: TextStyle(
                                            color: Color(0xFF000000),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13)))),
                          ),
                        ],
                      ]),
                ))),
        const SizedBox(height: 20),
        // Recent settled trips
        _sectionTitle("RECENTLY SETTLED",
            icon: Icons.check_circle_rounded, color: _green),
        ...widget.ledgers.where((l) => l.partyPending <= 0).take(5).map((l) =>
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: _green, width: 2))),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(l.partyName,
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                          Text(l.date,
                              style: const TextStyle(
                                  color: Color(0xFF000000), fontSize: 11))
                        ])),
                    Text(_f(l.freightBilled),
                        style: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w900)),
                  ]),
            )),
      ]);

  Widget _infoChip(String l, String v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: c.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withOpacity(0.25))),
        child: Column(children: [
          Text(v,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w900, fontSize: 12)),
          Text(l,
              style:
                  const TextStyle(color: Color(0xFF000000), fontSize: 9))
        ]),
      );

  // â”€â”€ TAB 3: Fleet Control â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _tabFleet() {
    final fleet = widget.fleet;
    final complianceOk =
        fleet.where((a) => a.docs.every((d) => d.isUploaded)).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Fleet summary
      Row(children: [
        Expanded(
            child: _metricCard("Total Vehicles", "${fleet.length}",
                Icons.local_shipping_rounded, _accent)),
        const SizedBox(width: 10),
        Expanded(
            child: _metricCard(
                "Compliant", "$complianceOk", Icons.verified_rounded, _green,
                sub: "${fleet.length - complianceOk} pending")),
      ]),
      const SizedBox(height: 16),
      _sectionTitle("VEHICLE REGISTER",
          icon: Icons.format_list_bulleted_rounded, color: _accent),
      ...fleet.map((a) {
        final uploadedDocs = a.docs.where((d) => d.isUploaded).length;
        final totalDocs = a.docs.length;
        final isCompliant = uploadedDocs == totalDocs;
        final tripCount =
            widget.ledgers.where((l) => l.vehicleNo == a.number).length;
        final revenue = widget.ledgers
            .where((l) => l.vehicleNo == a.number)
            .fold(0.0, (s, l) => s + l.freightBilled);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isCompliant
                      ? _green.withOpacity(0.2)
                      : _red.withOpacity(0.25))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: _accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.local_shipping_rounded,
                      color: Color(0xFFFB8C00), size: 20)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(a.number,
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 0.5)),
                    Text("${a.type} â€¢ ${a.axleCount} axle â€¢ ${a.payload}",
                        style: const TextStyle(
                            color: Color(0xFF000000), fontSize: 11)),
                  ])),
              _statusBadge(
                  isCompliant ? "COMPLIANT" : "$uploadedDocs/$totalDocs DOCS",
                  isCompliant ? _green : _amber),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _statChip(Icons.route_rounded, "$tripCount trips", _accent),
              const SizedBox(width: 8),
              _statChip(Icons.currency_rupee_rounded, _f(revenue), _green),
              const SizedBox(width: 8),
              _statChip(
                  Icons.tire_repair_rounded, "${a.tyreCount} tyres", _purple),
            ]),
            if (!isCompliant) ...[
              const SizedBox(height: 10),
              const Text("MISSING DOCUMENTS",
                  style: TextStyle(
                      color: Color(0xFFFB8C00),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: a.docs
                      .where((d) => !d.isUploaded)
                      .map((d) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: _red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border:
                                    Border.all(color: _red.withOpacity(0.3))),
                            child: Text(d.name,
                                style: const TextStyle(
                                    color: Color(0xFFE53E3E),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)),
                          ))
                      .toList()),
            ],
          ]),
        );
      }),
    ]);
  }

  Widget _statChip(IconData icon, String val, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(val,
              style: TextStyle(
                  color: c, fontSize: 11, fontWeight: FontWeight.w700))
        ]),
      );

  // â”€â”€ TAB 4: Driver Control â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _tabDrivers() {
    final filtered = _searchQuery.isEmpty
        ? widget.drivers
        : widget.drivers
            .where((d) =>
                d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                d.phone.contains(_searchQuery))
            .toList();
    final totalBalance = widget.drivers.fold(0.0, (s, d) => s + d.balance);
    final verified = widget.drivers.where((d) => d.isVerified).length;
    return Column(children: [
      // Summary row
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          Expanded(
              child: _metricCard("Drivers", "${widget.drivers.length}",
                  Icons.badge_rounded, _purple)),
          const SizedBox(width: 10),
          Expanded(
              child: _metricCard(
                  "Verified", "$verified", Icons.verified_rounded, _green)),
          const SizedBox(width: 10),
          Expanded(
              child: _metricCard(
                  "Net Balance",
                  _f(totalBalance),
                  Icons.account_balance_wallet_rounded,
                  totalBalance >= 0 ? _green : _red)),
        ]),
      ),
      // Search
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          decoration: InputDecoration(
              labelText: "Search driversâ€¦",
              prefixIcon: const Icon(Icons.search,
                  color: Color(0xFF000000), size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E2D4A))),
              filled: true,
              fillColor: _card2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
          style: const TextStyle(color: Color(0xFF000000)),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
      ),
      Expanded(
          child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
            ...filtered.map((d) {
              final trips =
                  widget.ledgers.where((l) => l.driverName == d.name).length;
              final dRev = widget.ledgers
                  .where((l) => l.driverName == d.name)
                  .fold(0.0, (s, l) => s + l.freightBilled);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: d.isVerified
                            ? _green.withOpacity(0.2)
                            : _amber.withOpacity(0.2))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                            radius: 22,
                            backgroundColor: _purple.withOpacity(0.15),
                            child: Text(
                                d.name.isNotEmpty
                                    ? d.name[0].toUpperCase()
                                    : "D",
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    color: Color(0xFF8B5CF6)))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Flexible(
                                    child: Text(d.name,
                                        style: const TextStyle(
                                            color: Color(0xFF000000),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15),
                                        overflow: TextOverflow.ellipsis)),
                                const SizedBox(width: 6),
                                if (d.isVerified)
                                  const Icon(Icons.verified_rounded,
                                      color: Color(0xFFFB8C00), size: 14)
                              ]),
                              Text(d.phone,
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 12)),
                            ])),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_f(d.balance.abs()),
                                  style: TextStyle(
                                      color: d.balance >= 0 ? _green : _red,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15)),
                              Text(d.balance >= 0 ? "To Pay" : "Owes",
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 9)),
                            ]),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _statChip(Icons.route_rounded, "$trips trips", _accent),
                        const SizedBox(width: 8),
                        _statChip(
                            Icons.currency_rupee_rounded, _f(dRev), _green),
                        const SizedBox(width: 8),
                        if (d.monthlySalary > 0)
                          _statChip(Icons.payments_rounded,
                              "${_f(d.monthlySalary)}/mo", _purple),
                      ]),
                      if (d.aadharNum.isNotEmpty || d.dlNum.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          if (d.aadharNum.isNotEmpty)
                            _statChip(Icons.fingerprint, "Aadhaar âœ“", _cyan),
                          if (d.dlNum.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _statChip(
                                Icons.card_membership_rounded, "DL âœ“", _green)
                          ],
                        ]),
                      ],
                      // Quick credit/debit actions
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: _actionBtn("Pay Salary", _green,
                                () => _quickDriverAction(d, "salary"),
                                icon: Icons.payments_rounded)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _actionBtn("Give Advance", _amber,
                                () => _quickDriverAction(d, "advance"),
                                icon: Icons.money_rounded)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _actionBtn("Add Penalty", _red,
                                () => _quickDriverAction(d, "penalty"),
                                icon: Icons.gavel_rounded)),
                      ]),
                    ]),
              );
            }),
          ])),
    ]);
  }

  void _quickDriverAction(Driver d, String action) {
    final ctrl = TextEditingController(
        text: action == "salary" ? d.monthlySalary.toStringAsFixed(0) : "");
    final noteCtrl = TextEditingController();
    final colors = {"salary": _green, "advance": _amber, "penalty": _red};
    final icons = {
      "salary": Icons.payments_rounded,
      "advance": Icons.money_rounded,
      "penalty": Icons.gavel_rounded
    };
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              backgroundColor: _card2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(children: [
                Icon(icons[action]!, color: colors[action]!),
                const SizedBox(width: 8),
                Text(
                    "${action == "salary" ? "Pay Salary" : action == "advance" ? "Give Advance" : "Add Penalty"} â€” ${d.name}",
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontWeight: FontWeight.w800,
                        fontSize: 15))
              ]),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 20,
                        fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                        labelText: "Amount (â‚¹)",
                        prefixIcon:
                            Icon(Icons.currency_rupee, color: colors[action]!),
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2)))),
                const SizedBox(height: 10),
                TextField(
                    controller: noteCtrl,
                    style: const TextStyle(color: Color(0xFF000000)),
                    decoration: InputDecoration(
                        labelText: "Notes",
                        filled: true,
                        fillColor: const Color(0xFFFFF8E1),
                        labelStyle: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        floatingLabelStyle: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFFB8C00))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFFFB8C00), width: 2)))),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text("Cancel",
                        style: TextStyle(color: Color(0xFF000000)))),
                GestureDetector(
                  onTap: () {
                    final amt = double.tryParse(ctrl.text) ?? 0;
                    if (amt <= 0) return;
                    final txType = action == "salary"
                        ? DriverTxType.salary
                        : action == "advance"
                            ? DriverTxType.advance
                            : DriverTxType.penalty;
                    final sign =
                        action == "penalty" || action == "advance" ? -1 : 1;
                    setState(() {
                      d.transactions.insert(
                          0,
                          DriverTx(
                              date:
                                  "${DateTime.now().day}/${DateTime.now().month}",
                              type: txType,
                              amount: amt * sign,
                              note: noteCtrl.text.isNotEmpty
                                  ? noteCtrl.text
                                  : action));
                      d.balance += amt * sign;
                    });
                    widget.onUpdate();
                    Navigator.pop(c);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        backgroundColor: colors[action]!,
                        behavior: SnackBarBehavior.floating,
                        content:
                            Text("âœ… â‚¹${amt.toStringAsFixed(0)} â€” ${d.name}")));
                  },
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                          color: colors[action]!,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text("Confirm",
                          style: TextStyle(
                              color: Color(0xFF000000),
                              fontWeight: FontWeight.w800))),
                ),
              ],
            ));
  }

  // â”€â”€ TAB 5: Subscription / Users â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _tabSubscription() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        // Current plan
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              widget.subscription.tierColor,
              widget.subscription.tierColor.withOpacity(0.5),
              _card
            ], stops: const [
              0,
              0.4,
              1
            ]),
            borderRadius: BorderRadius.circular(20),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFF000000), size: 20),
              const SizedBox(width: 8),
              Text(widget.subscription.tierName,
                  style: const TextStyle(
                      color: Color(0xFF000000),
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: 1))
            ]),
            const SizedBox(height: 6),
            Text(
                "${widget.subscription.tripsUsedThisMonth} trips this month â€¢ ${widget.subscription.maxVehicles} max vehicles â€¢ ${widget.subscription.maxUsers} users",
                style: const TextStyle(color: Color(0x701C1917), fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 20),
        _sectionTitle("CHANGE PLAN",
            icon: Icons.upgrade_rounded, color: _accent),
        ...SubscriptionTier.values.map((tier) {
          final names = ["FREE", "PRO", "BUSINESS", "ENTERPRISE"];
          final colors = [
            Colors.grey,
            Colors.blueAccent,
            Colors.amber.shade700,
            const Color(0xFFFB8C00)
          ];
          final prices = ["â‚¹0", "â‚¹799/mo", "â‚¹4,999/mo", "â‚¹9,999/mo"];
          final isCurrent = _subTier == tier;
          return GestureDetector(
            onTap: () {
              if (!isCurrent) {
                setState(() {
                  _subTier = tier;
                  widget.subscription.tier = tier;
                });
                widget.onUpdate();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: colors[tier.index],
                    behavior: SnackBarBehavior.floating,
                    content: Text("Plan changed to ${names[tier.index]}")));
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCurrent ? colors[tier.index].withOpacity(0.15) : _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isCurrent ? colors[tier.index] : _border,
                    width: isCurrent ? 2 : 1),
              ),
              child: Row(children: [
                Icon(Icons.workspace_premium_rounded,
                    color: colors[tier.index], size: 22),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(names[tier.index],
                          style: TextStyle(
                              color: isCurrent
                                  ? const Color(0xFFFFF8E1)
                                  : const Color(0xFF000000),
                              fontWeight: FontWeight.w900,
                              fontSize: 14)),
                      Text(prices[tier.index],
                          style: TextStyle(
                              color: colors[tier.index],
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ])),
                if (isCurrent)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: colors[tier.index].withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text("ACTIVE",
                          style: TextStyle(
                              color: colors[tier.index],
                              fontWeight: FontWeight.w900,
                              fontSize: 10))),
              ]),
            ),
          );
        }),
        const SizedBox(height: 20),
        _sectionTitle("USER PROFILE", icon: Icons.person_rounded, color: _cyan),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border)),
          child: Column(children: [
            _profileRow("Company", widget.userProfile.companyName,
                Icons.business_rounded, _accent),
            _profileRow(
                "GSTIN",
                widget.userProfile.gstin.isNotEmpty
                    ? widget.userProfile.gstin
                    : "Not set",
                Icons.receipt_rounded,
                _green),
            _profileRow(
                "Phone", widget.userProfile.phone, Icons.phone_rounded, _cyan),
            _profileRow(
                "Bank",
                widget.userProfile.bankName.isNotEmpty
                    ? "${widget.userProfile.bankName} â€¢ ${widget.userProfile.bankIfsc}"
                    : "Not configured",
                Icons.account_balance_rounded,
                _purple),
            _profileRow(
                "Email",
                widget.userProfile.email.isNotEmpty
                    ? widget.userProfile.email
                    : "Not set",
                Icons.email_rounded,
                _amber),
          ]),
        ),
      ]);

  Widget _profileRow(String label, String val, IconData icon, Color c) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: c, size: 14)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                Text(val,
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ])),
        ]),
      );

  // â”€â”€ TAB 6: System / Config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _tabSystem() => ListView(padding: const EdgeInsets.all(16), children: [
        // App health
        _sectionTitle("SYSTEM STATUS",
            icon: Icons.monitor_heart_rounded, color: _green),
        _sysRow(
            Icons.api_rounded,
            "Google Maps API",
            AppConfig.googleMapsApiKey.isNotEmpty
                ? "Connected â€¢ ${AppConfig.googleMapsApiKey.substring(0, 12)}..."
                : "Not Set",
            AppConfig.googleMapsApiKey.isNotEmpty ? _green : _red),
        _sysRow(
            Icons.local_fire_department_rounded,
            "Firebase",
            FirebaseService.isReady ? "Connected & Ready" : "Offline Mode",
            FirebaseService.isReady ? _green : _amber),
        _sysRow(Icons.phone_android_rounded, "App Version",
            "Route Master ERP v${AppConfig.appVersion}", _cyan),
        _sysRow(Icons.storage_rounded, "Data Trips",
            "${widget.ledgers.length} records", _accent),
        _sysRow(Icons.local_shipping_rounded, "Fleet",
            "${widget.fleet.length} vehicles", _purple),
        const SizedBox(height: 20),
        // Required APIs checklist
        _sectionTitle("API CHECKLIST",
            icon: Icons.checklist_rounded, color: _amber),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border)),
          child: Column(children: [
            _apiCheck("Places API", true, "City & factory autocomplete"),
            _apiCheck(
                "Distance Matrix API", true, "KM calculation (Uber-style)"),
            _apiCheck("Geocoding API", true, "Address to coordinates"),
            _apiCheck("Cloud Vision API", true, "Document OCR scanning"),
            _apiCheck(
                "Firebase Phone Auth", FirebaseService.isReady, "OTP login"),
            _apiCheck("Firestore", FirebaseService.isReady, "Cloud data sync"),
          ]),
        ),
        const SizedBox(height: 20),
        // Export actions
        _sectionTitle("DATA EXPORT",
            icon: Icons.download_rounded, color: _accent),
        _actionTile(Icons.table_chart_rounded, "Export Full Ledger CSV",
            "All ${widget.ledgers.length} trips", _green, () {
          final sb = StringBuffer(
              "ID,Date,Party,Vehicle,Route,Freight,Received,Pending,Profit\n");
          for (final l in widget.ledgers) {
            sb.writeln(
                '${l.id},${l.date},"${l.partyName}",${l.vehicleNo},"${l.route}",${l.freightBilled},${l.paymentReceived},${l.partyPending},${l.tripProfit}');
          }
          Clipboard.setData(ClipboardData(text: sb.toString()));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              content: Text("âœ… CSV copied to clipboard")));
        }),
        const SizedBox(height: 8),
        _actionTile(Icons.people_rounded, "Export Driver Ledger",
            "${widget.drivers.length} drivers", _purple, () {
          final sb = StringBuffer("Name,Phone,Balance,Salary\n");
          for (final d in widget.drivers) {
            sb.writeln(
                '"${d.name}",${d.phone},${d.balance},${d.monthlySalary}');
          }
          Clipboard.setData(ClipboardData(text: sb.toString()));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              backgroundColor: Colors.purple,
              behavior: SnackBarBehavior.floating,
              content: Text("âœ… Driver data copied")));
        }),
        const SizedBox(height: 20),
        // Danger zone
        _sectionTitle("âš ï¸ DANGER ZONE",
            icon: Icons.warning_rounded, color: _red),
        GestureDetector(
          onTap: () => showDialog(
              context: context,
              builder: (c) => AlertDialog(
                    backgroundColor: _card2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    title: const Row(children: [
                      Icon(Icons.delete_forever,
                          color: Color(0xFFE53E3E)),
                      SizedBox(width: 8),
                      Text("Factory Reset",
                          style: TextStyle(
                              color: Color(0xFF000000),
                              fontWeight: FontWeight.w900))
                    ]),
                    content: const Text(
                        "This will permanently erase ALL data â€” trips, fleet, drivers, settings. This CANNOT be undone.",
                        style: TextStyle(color: Color(0xFF000000))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text("Cancel",
                              style:
                                  TextStyle(color: Color(0xFF000000)))),
                      GestureDetector(
                          onTap: () {
                            Navigator.pop(c);
                            Navigator.pop(context);
                            widget.onFactoryReset();
                          },
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                  color: _red,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Text("WIPE ALL DATA",
                                  style: TextStyle(
                                      color: Color(0xFF000000),
                                      fontWeight: FontWeight.w800)))),
                    ],
                  )),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _red.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.delete_forever_rounded,
                  color: Color(0xFFE53E3E), size: 22),
              SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text("Factory Reset",
                        style: TextStyle(
                            color: Color(0xFFE53E3E),
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    Text("Erase all app data permanently",
                        style: TextStyle(
                            color: Color(0xFF000000), fontSize: 12))
                  ])),
              Icon(Icons.chevron_right, color: Color(0xFF000000))
            ]),
          ),
        ),
      ]);

  Widget _sysRow(IconData icon, String label, String val, Color c) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: c, width: 3))),
        child: Row(
          children: [
            Icon(icon, color: c, size: 18),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  Text(val,
                      style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis)
                ]))
          ],
        ),
      );

  Widget _apiCheck(String name, bool ok, String desc) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  color: ok ? _green.withOpacity(0.15) : _red.withOpacity(0.15),
                  shape: BoxShape.circle),
              child: Icon(ok ? Icons.check : Icons.close,
                  size: 13, color: ok ? _green : _red)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        color: Color(0xFF000000),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Text(desc,
                    style: const TextStyle(
                        color: Color(0xFF000000), fontSize: 10))
              ])),
        ]),
      );

  Widget _actionTile(IconData icon, String title, String sub, Color c,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.withOpacity(0.2))),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: c, size: 18)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: Color(0xFF000000),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(sub,
                      style: const TextStyle(
                          color: Color(0xFF000000), fontSize: 11))
                ])),
            Icon(Icons.arrow_forward_ios, color: c, size: 13)
          ]),
        ),
      );

  // â”€â”€ MAIN BUILD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final tabLabels = [
      "Overview",
      "Finance",
      "Fleet",
      "Drivers",
      "Plans",
      "System"
    ];
    final tabIcons = [
      Icons.analytics_rounded,
      Icons.account_balance_rounded,
      Icons.local_shipping_rounded,
      Icons.badge_rounded,
      Icons.workspace_premium_rounded,
      Icons.settings_rounded
    ];
    final tabColors = [
      _accent,
      _amber,
      _green,
      _purple,
      const Color(0xFFFB8C00),
      _cyan
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
            decoration: const BoxDecoration(color: Color(0xFFFBF7F0))),
        iconTheme: const IconThemeData(color: Color(0xFF000000)),
        elevation: 0,
        title: Row(children: [
          Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xFF5C3D2E),
                    Color(0xFFFB8C00)
                  ]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFFFB8C00).withOpacity(0.4),
                        blurRadius: 10)
                  ]),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: Color(0xFF000000), size: 18)),
          const SizedBox(width: 10),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("MASTER ADMIN",
                    style: TextStyle(
                        color: Color(0xFF000000),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.5)),
                Text("Route Master ERP v${AppConfig.appVersion}",
                    style: const TextStyle(
                        color: Color(0xFF7C86A0),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
              ]),
        ]),
        actions: [
          Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: Color(0xFFE53E3E), size: 8),
                SizedBox(width: 4),
                Text("ADMIN",
                    style: TextStyle(
                        color: Color(0xFFE53E3E),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1))
              ])),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
                children: tabLabels
                    .asMap()
                    .entries
                    .map((e) => GestureDetector(
                          onTap: () {
                            _tabs.animateTo(e.key);
                            setState(() => _selectedTab = e.key);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTab == e.key
                                  ? tabColors[e.key].withOpacity(0.2)
                                  : const Color(0xFFFFF8E1).withOpacity(0.04),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _selectedTab == e.key
                                      ? tabColors[e.key].withOpacity(0.6)
                                      : const Color(0xFFFFF8E1)
                                          .withOpacity(0.08)),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(tabIcons[e.key],
                                  size: 13,
                                  color: _selectedTab == e.key
                                      ? tabColors[e.key]
                                      : const Color(0xFF000000)),
                              const SizedBox(width: 5),
                              Text(e.value,
                                  style: TextStyle(
                                      color: _selectedTab == e.key
                                          ? tabColors[e.key]
                                          : const Color(0xFF000000),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11)),
                            ]),
                          ),
                        ))
                    .toList()),
          ),
        ),
      ),
      body: TabBarView(
          controller: _tabs,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _tabOverview(),
            _tabFinance(),
            _tabFleet(),
            _tabDrivers(),
            _tabSubscription(),
            _tabSystem(),
          ]),
    );
  }
}

class KredXScreen extends StatefulWidget {
  final List<TripLedger> ledgers;
  final List<KredXApplication> kredxApps;
  final Function(KredXApplication) onApply;
  final VoidCallback onUpdate;
  const KredXScreen(
      {super.key,
      required this.ledgers,
      required this.kredxApps,
      required this.onApply,
      required this.onUpdate});
  @override
  State<KredXScreen> createState() => _KredXScreenState();
}

class _KredXScreenState extends State<KredXScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<TripLedger> get eligible => widget.ledgers
      .where((l) =>
          l.partyPending >= 5000 &&
          !widget.kredxApps.any((a) => a.invoiceLedgerId == l.id))
      .toList();
  Widget _kr(String l, String v, {bool b = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l,
            style: TextStyle(
                fontWeight: b ? FontWeight.w900 : FontWeight.w600,
                color: Color(0xFFCBD5E1),
                fontSize: 13)),
        Text(v,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: b ? 15 : 13,
                color: const Color(0xFF000000)))
      ]));
  void _apply(TripLedger ledger) {
    double max = ledger.partyPending * 0.85;
    double req = max;
    int tenure = 30;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (c) => StatefulBuilder(
            builder: (c2, setSt) => Container(
                  decoration: const BoxDecoration(
                      color: Color(0xFFFBF7F0),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28))),
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(c2).viewInsets.bottom,
                      left: 24,
                      right: 24,
                      top: 28),
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Row(children: [
                          Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(Icons.account_balance,
                                  color: Colors.amber[700], size: 28)),
                          const SizedBox(width: 12),
                          const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("KredX Invoice Finance",
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900)),
                                Text("Get paid early. Pay later.",
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 12))
                              ])
                        ]),
                        const SizedBox(height: 22),
                        Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.amber[200]!)),
                            child: Column(children: [
                              _kr("Party", ledger.partyName),
                              _kr("Invoice",
                                  "â‚¹${ledger.partyPending.toStringAsFixed(0)}"),
                              _kr("You Get (85%)",
                                  "â‚¹${max.toStringAsFixed(0)}"),
                              _kr("Interest Rate", "1.5% / month")
                            ])),
                        const SizedBox(height: 20),
                        const Text("Request Amount",
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF000000))),
                        Slider(
                            value: req,
                            min: 5000,
                            max: max > 5000 ? max : 5001,
                            activeColor: Colors.amber[700],
                            label: "â‚¹${req.toStringAsFixed(0)}",
                            onChanged: (v) => setSt(() => req = v)),
                        Center(
                            child: Text("â‚¹${req.toStringAsFixed(0)}",
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.amber[700]))),
                        const SizedBox(height: 16),
                        Row(
                            children: [30, 60, 90]
                                .map((t) => Expanded(
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: GestureDetector(
                                            onTap: () =>
                                                setSt(() => tenure = t),
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10),
                                                decoration: BoxDecoration(
                                                    color: tenure == t
                                                        ? const Color(
                                                            0xFF0D1F14)
                                                        : Colors.grey[100],
                                                    borderRadius:
                                                        BorderRadius.circular(10)),
                                                child: Center(child: Text("$t Days", style: TextStyle(fontWeight: FontWeight.bold, color: tenure == t ? const Color(0xFFFFF8E1) : Colors.black))))))))
                                .toList()),
                        const SizedBox(height: 14),
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10)),
                            child: Column(children: [
                              _kr("Est. Interest",
                                  "â‚¹${(req * 0.015 * (tenure / 30)).toStringAsFixed(0)}"),
                              _kr("Net Disbursed",
                                  "â‚¹${(req - req * 0.015 * (tenure / 30)).toStringAsFixed(0)}",
                                  b: true)
                            ])),
                        const SizedBox(height: 18),
                        SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber[700],
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14))),
                                onPressed: () {
                                  final app = KredXApplication(
                                      id: "KX${math.Random().nextInt(99999)}",
                                      invoiceLedgerId: ledger.id,
                                      partyName: ledger.partyName,
                                      invoiceAmount: ledger.partyPending,
                                      requestedAmount: req,
                                      status: KredXStatus.submitted,
                                      appliedDate:
                                          "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
                                      tenureDays: tenure);
                                  widget.onApply(app);
                                  setState(() {});
                                  Navigator.pop(c);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          backgroundColor: Colors.green,
                                          behavior: SnackBarBehavior.floating,
                                          content: Text(
                                              "âœ… KredX application submitted!")));
                                },
                                child: const Text("Submit to KredX",
                                    style: TextStyle(
                                        color: Color(0xFF000000),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)))),
                        const SizedBox(height: 24),
                      ])),
                )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: const Color(0xFFFFF8E1),
            iconTheme: const IconThemeData(color: Color(0xFF000000)),
            title: Row(children: [
              Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.amber[700],
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.account_balance,
                      color: Color(0xFF000000), size: 18)),
              const SizedBox(width: 10),
              const Text("KredX Invoice Finance",
                  style: TextStyle(
                      color: Color(0xFF000000),
                      fontWeight: FontWeight.w900,
                      fontSize: 16))
            ]),
            bottom: TabBar(
                controller: _tabs,
                indicatorColor: Colors.amber,
                labelColor: Colors.amber,
                unselectedLabelColor: Color(0x541A3A2A),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: "Eligible Invoices"),
                  Tab(text: "My Applications")
                ])),
        body: TabBarView(controller: _tabs, children: [
          eligible.isEmpty
              ? const Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 60, color: Colors.grey),
                      SizedBox(height: 12),
                      Text("No eligible invoices",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.grey)),
                      Text("Invoices with â‚¹5000+ pending qualify",
                          style: TextStyle(color: Colors.grey))
                    ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: eligible.length,
                  itemBuilder: (_, i) {
                    final l = eligible[i];
                    return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                            color: const Color(0xFF000000),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10)
                            ]),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(l.partyName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 16)),
                                          Text("${l.vehicleNo} â€¢ ${l.date}",
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12))
                                        ]),
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                              "â‚¹${l.partyPending.toStringAsFixed(0)}",
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 18,
                                                  color: Colors.orange)),
                                          const Text("pending",
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11))
                                        ])
                                  ]),
                              const Divider(height: 16),
                              Row(children: [
                                Expanded(
                                    child: Column(children: [
                                  const Text("Invoice",
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                  Text("â‚¹${l.freightBilled.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900))
                                ])),
                                Expanded(
                                    child: Column(children: [
                                  const Text("You Get (85%)",
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      "â‚¹${(l.partyPending * 0.85).toStringAsFixed(0)}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.green))
                                ]))
                              ]),
                              const SizedBox(height: 12),
                              SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.amber[700],
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10))),
                                      onPressed: () => _apply(l),
                                      icon: const Icon(Icons.account_balance,
                                          color: Color(0xFF000000),
                                          size: 16),
                                      label: const Text("Apply for Advance",
                                          style: TextStyle(
                                              color: Color(0xFF000000),
                                              fontWeight: FontWeight.bold))))
                            ]));
                  }),
          widget.kredxApps.isEmpty
              ? const Center(
                  child: Text("No applications yet",
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.kredxApps.length,
                  itemBuilder: (_, i) {
                    final app = widget.kredxApps[i];
                    return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                            color: const Color(0xFF000000),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10)
                            ]),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(app.partyName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15)),
                                          Text("Applied: ${app.appliedDate}",
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12))
                                        ]),
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                            color: app.statusColor
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: app.statusColor
                                                    .withOpacity(0.4))),
                                        child: Text(app.statusLabel,
                                            style: TextStyle(
                                                color: app.statusColor,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12)))
                                  ]),
                              const Divider(height: 16),
                              Row(children: [
                                Expanded(
                                    child: Column(children: [
                                  const Text("Requested",
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      "â‚¹${app.requestedAmount.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.orange))
                                ])),
                                Expanded(
                                    child: Column(children: [
                                  const Text("Approved",
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      app.approvedAmount > 0
                                          ? "â‚¹${app.approvedAmount.toStringAsFixed(0)}"
                                          : "Pending",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.green))
                                ])),
                                Expanded(
                                    child: Column(children: [
                                  const Text("Tenure",
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                  Text("${app.tenureDays}d",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.blue))
                                ]))
                              ])
                            ]));
                  }),
        ]),
      );
}

// ================================================================
// SUBSCRIPTION SCREEN
// ================================================================
class SubscriptionScreen extends StatelessWidget {
  final SubscriptionInfo current;
  final Function(SubscriptionTier) onUpgrade;
  const SubscriptionScreen(
      {super.key, required this.current, required this.onUpgrade});
  Widget _feat(bool a, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(a ? Icons.check_circle : Icons.remove_circle_outline,
            size: 16, color: a ? const Color(0xFFFB8C00) : Color(0x241A3A2A)),
        const SizedBox(width: 10),
        Text(t,
            style: TextStyle(
                color: a ? const Color(0xFFFFF8E1) : Color(0x381A3A2A),
                fontSize: 13,
                fontWeight: a ? FontWeight.w600 : FontWeight.normal))
      ]));
  Widget _plan(BuildContext ctx, SubscriptionTier tier, String name,
      String price, String period, Color color, List<Widget> feats,
      {bool rec = false}) {
    final isCur = current.tier == tier;
    return Container(
        decoration: BoxDecoration(
            color: const Color(0xFFFB8C00),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isCur ? color : color.withOpacity(0.3),
                width: isCur ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20))),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(name,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                    if (rec) ...[
                      const SizedBox(width: 8),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8)),
                          child: const Text("BEST VALUE",
                              style: TextStyle(
                                  color: Color(0xFFFFF8E1),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900)))
                    ],
                    if (isCur) ...[
                      const SizedBox(width: 8),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green)),
                          child: const Text("ACTIVE",
                              style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900)))
                    ]
                  ]),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(price,
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontWeight: FontWeight.w900,
                            fontSize: 26)),
                    const SizedBox(width: 4),
                    Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(period,
                            style: const TextStyle(
                                color: Color(0xFF57534E), fontSize: 12)))
                  ])
                ])
              ])),
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...feats,
                    const SizedBox(height: 12),
                    if (!isCur)
                      SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: color,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                              onPressed: () {
                                onUpgrade(tier);
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                    backgroundColor: color,
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                        "Upgraded to $name! Features unlocked.")));
                              },
                              child: Text(
                                  tier == SubscriptionTier.free
                                      ? "Downgrade to Free"
                                      : "Upgrade to $name",
                                  style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)))),
                    if (isCur)
                      Container(
                          width: double.infinity,
                          height: 44,
                          decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green)),
                          child: const Center(
                              child: Text("âœ“ Your Current Plan",
                                  style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold)))),
                  ])),
        ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFFF8E1),
        appBar: AppBar(
            backgroundColor: const Color(0xFFFFF8E1),
            elevation: 0,
            iconTheme: const IconThemeData(color: Color(0xFF000000)),
            title: const Text("Choose Your Plan",
                style: TextStyle(
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.w900))),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Color(0x101C1917),
                      borderRadius: BorderRadius.circular(18)),
                  child: Row(children: [
                    Icon(Icons.workspace_premium,
                        color: current.tierColor, size: 32),
                    const SizedBox(width: 14),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Current Plan",
                              style: TextStyle(
                                  color: Color(0x601C1917),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text(current.tierName,
                              style: TextStyle(
                                  color: current.tierColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900))
                        ]),
                    const Spacer(),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                              "${current.tripsUsedThisMonth}/${current.tier == SubscriptionTier.free ? '10' : 'âˆž'}",
                              style: const TextStyle(
                                  color: Color(0xFF000000),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18)),
                          const Text("trips this month",
                              style: TextStyle(
                                  color: Color(0x601C1917), fontSize: 11))
                        ])
                  ])),
              const SizedBox(height: 20),
              _plan(context, SubscriptionTier.free, "FREE", "â‚¹0", "Forever",
                  Colors.grey, [
                _feat(true, "10 trips per month"),
                _feat(true, "Basic ledger & fleet"),
                _feat(true, "Driver roster"),
                _feat(false, "PDF Export (LR & Invoice)"),
                _feat(false, "Live GPS Tracking"),
                _feat(false, "KredX Financing")
              ]),
              const SizedBox(height: 14),
              _plan(context, SubscriptionTier.pro, "PRO", "â‚¹799", "/month",
                  Colors.blueAccent, [
                _feat(true, "Unlimited trips"),
                _feat(true, "PDF Export (LR & Invoice)"),
                _feat(true, "Live GPS Tracking"),
                _feat(true, "Route auto-calculator"),
                _feat(true, "Priority support"),
                _feat(false, "KredX Financing")
              ]),
              const SizedBox(height: 14),
              _plan(
                  context,
                  SubscriptionTier.business,
                  "BUSINESS",
                  "â‚¹4,999",
                  "/month",
                  Colors.amber.shade700,
                  [
                    _feat(true, "Everything in PRO"),
                    _feat(true, "KredX Invoice Financing"),
                    _feat(true, "Instant advances on invoices"),
                    _feat(true, "3 sub-users"),
                    _feat(true, "Up to 50 vehicles"),
                    _feat(true, "Advanced P&L reports"),
                    _feat(true, "Dedicated account manager")
                  ],
                  rec: true),
              const SizedBox(height: 14),
              _plan(context, SubscriptionTier.enterprise, "ENTERPRISE",
                  "â‚¹9,999", "/month", const Color(0xFFFB8C00), [
                _feat(true, "Everything in BUSINESS"),
                _feat(true, "Unlimited vehicles (50+)"),
                _feat(true, "10 staff / sub-user logins"),
                _feat(true, "Custom company branding"),
                _feat(true, "White-label PDF reports"),
                _feat(true, "API access for integration"),
                _feat(true, "Priority 24x7 phone support"),
                _feat(true, "Onboarding & training session")
              ]),
              const SizedBox(height: 20),
              const Text("All plans include local data backup. Cancel anytime.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0x381C1917), fontSize: 11)),
            ])),
      );
}

// ================================================================
// LIVE TRACKING SCREEN
// ================================================================
class LiveTrackingScreen extends StatefulWidget {
  final String route, vehicleNo;
  final double distanceKm;
  final String tripId;
  const LiveTrackingScreen(
      {super.key,
      required this.route,
      required this.vehicleNo,
      this.distanceKm = 0,
      this.tripId = ''});
  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with TickerProviderStateMixin {
  double _prog = 0.0;
  Timer? _timer;
  // Live location from Firebase / simulated
  double? _lat, _lng;
  final bool _driverSharing = false; // true when driver has enabled sharing
  late AnimationController _pulse;
  late TabController _tabs;
  late int _eta;
  String _status = "On Route";
  final List<String> _log = [];
  final bool _loadingEmergency = false;

  // Hardcoded emergency data (Google Places API fallback)
  final List<Map<String, dynamic>> _hospitals = [
    {
      'name': 'Civil Hospital',
      'dist': '2.3 km',
      'phone': '108',
      'icon': Icons.local_hospital
    },
    {
      'name': 'Primary Health Centre',
      'dist': '4.1 km',
      'phone': '104',
      'icon': Icons.medical_services
    },
    {
      'name': 'Apollo Clinic',
      'dist': '5.8 km',
      'phone': '1066',
      'icon': Icons.local_hospital
    },
  ];
  final List<Map<String, dynamic>> _repair = [
    {
      'name': 'National Highway Tyre Service',
      'dist': '1.2 km',
      'phone': '9876543210',
      'icon': Icons.tire_repair
    },
    {
      'name': 'Roadside Auto Works',
      'dist': '3.4 km',
      'phone': '9876500000',
      'icon': Icons.build
    },
    {
      'name': 'Diesel Pump & Mechanic',
      'dist': '4.7 km',
      'phone': '9123456789',
      'icon': Icons.local_gas_station
    },
  ];
  final List<Map<String, dynamic>> _emergency = [
    {
      'name': 'National Highway Helpline',
      'phone': '1033',
      'icon': Icons.sos,
      'color': Colors.red
    },
    {
      'name': 'Police Control Room',
      'phone': '100',
      'icon': Icons.local_police,
      'color': Colors.blue
    },
    {
      'name': 'Ambulance',
      'phone': '108',
      'icon': Icons.emergency,
      'color': Colors.red
    },
    {
      'name': 'Fire Department',
      'phone': '101',
      'icon': Icons.fire_truck,
      'color': Colors.orange
    },
    {
      'name': 'NHAI Toll Helpline',
      'phone': '1033',
      'icon': Icons.toll,
      'color': Colors.teal
    },
    {
      'name': 'Vehicle Breakdown (NHAI)',
      'phone': '1800-11-6886',
      'icon': Icons.car_repair,
      'color': Colors.purple
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    // Calculate ETA: avg HCV speed = 55 km/h on NH, 45 km/h city/state roads
    final km = widget.distanceKm > 0 ? widget.distanceKm : 600.0;
    _eta = (km / 52.0 * 60).round(); // minutes
    _log.insert(
        0, "${_t()} â€” Dispatched from ${widget.route.split('â†’').first.trim()}");
    _log.insert(0, "${_t()} â€” E-Way Bill verified & GPS active");
    _log.insert(0, "${_t()} â€” Live tracking started");
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() {
        if (_prog < 0.97) {
          _prog += 0.008 + math.Random().nextDouble() * 0.008;
          // ETA recalculated from actual distance
          final remainingKm = widget.distanceKm > 0
              ? widget.distanceKm * (1 - _prog)
              : 600 * (1 - _prog);
          _eta = (remainingKm / 52.0 * 60).round(); // 52 km/h avg
          if (_prog > 0.15 && _prog < 0.17) {
            _status = "Toll Plaza";
            _log.insert(0, "${_t()} â€” FASTag deducted at NH toll");
          }
          if (_prog > 0.35 && _prog < 0.37) {
            _status = "State Border";
            _log.insert(0, "${_t()} â€” Crossed state border, documents checked");
          }
          if (_prog > 0.55 && _prog < 0.57) {
            _status = "Driver Break";
            _log.insert(0, "${_t()} â€” Rest stop (30 min). ETA revised.");
          }
          if (_prog > 0.75 && _prog < 0.77) {
            _status = "Toll Plaza";
            _log.insert(0, "${_t()} â€” FASTag deducted at destination toll");
          }
          if (_prog > 0.88 && _prog < 0.90) {
            _status = "Approaching Destination";
            _log.insert(0, "${_t()} â€” ~${_fmtEta(_eta)} to destination");
          }
        } else {
          _status = "Arrived";
          if (!_log.first.contains("Arrived")) {
            _log.insert(0, "${_t()} â€” Vehicle arrived at destination");
          }
        }
      });
    });
  }

  String _t() {
    final t = DateTime.now();
    return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
  }

  String _fmtEta(int m) {
    if (m <= 0) return "Arrived";
    int h = m ~/ 60, mn = m % 60;
    return h > 0 ? "${h}h ${mn}m" : "${mn}m";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Widget _emergencyCard(Map<String, dynamic> item, {bool isCall = true}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
            ]),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color:
                      (item['color'] as Color? ?? Colors.blue).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(item['icon'] as IconData,
                  color: item['color'] as Color? ?? Colors.blue, size: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item['name'] as String,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                if (item['dist'] != null)
                  Text(item['dist'] as String,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ])),
          if (isCall)
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  content: Text("Calling ${item['phone']}..."))),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.phone,
                        color: Color(0xFF000000), size: 14),
                    const SizedBox(width: 4),
                    Text(item['phone'] as String,
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontWeight: FontWeight.bold,
                            fontSize: 12))
                  ])),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFFFF8E1),
          iconTheme: const IconThemeData(color: Color(0xFF000000)),
          title: Text(widget.vehicleNo,
              style: const TextStyle(
                  color: Color(0xFF000000), fontWeight: FontWeight.w900)),
          actions: [
            Container(
                margin: const EdgeInsets.only(right: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.5))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: Colors.green
                                  .withOpacity(0.5 + _pulse.value * 0.5),
                              shape: BoxShape.circle))),
                  const SizedBox(width: 6),
                  const Text("LIVE",
                      style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w900,
                          fontSize: 12))
                ])),
          ],
          bottom: TabBar(
              controller: _tabs,
              indicatorColor: Colors.blueAccent,
              labelColor: const Color(0xFFFFF8E1),
              unselectedLabelColor: Color(0x541A3A2A),
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
              tabs: const [
                Tab(text: "Live Map"),
                Tab(text: "Hospitals"),
                Tab(text: "SOS & Repair")
              ]),
        ),
        body: TabBarView(controller: _tabs, children: [
          // Tab 1: Live Map
          Column(children: [
            Expanded(
                flex: 3,
                child: Container(
                    color: const Color(0xFF1A2744),
                    child: Stack(children: [
                      CustomPaint(
                          painter: _MapGridPainter(), size: Size.infinite),
                      Positioned(
                          left: 40,
                          right: 40,
                          top: 0,
                          bottom: 0,
                          child: Center(
                              child: Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: Color(0x241A3A2A),
                                      borderRadius:
                                          BorderRadius.circular(2))))),
                      Positioned(
                          left: 40,
                          right: 40,
                          top: 0,
                          bottom: 0,
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                  widthFactor: _prog,
                                  child: Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                          color: Colors.blueAccent,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.blueAccent
                                                    .withOpacity(0.5),
                                                blurRadius: 8)
                                          ]))))),
                      const Positioned(
                          left: 36,
                          top: 0,
                          bottom: 0,
                          child: Center(
                              child: Icon(Icons.circle,
                                  color: Colors.green, size: 14))),
                      const Positioned(
                          right: 36,
                          top: 0,
                          bottom: 0,
                          child: Center(
                              child: Icon(Icons.location_on,
                                  color: Colors.red, size: 22))),
                      Positioned(
                          left: 40 +
                              (_prog *
                                  (MediaQuery.of(context).size.width - 80)) -
                              14,
                          top: 0,
                          bottom: 0,
                          child: Center(
                              child: AnimatedBuilder(
                                  animation: _pulse,
                                  builder: (_, __) => Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                          color: Colors.blueAccent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.blueAccent
                                                    .withOpacity(0.4 +
                                                        _pulse.value * 0.4),
                                                blurRadius:
                                                    12 + _pulse.value * 8,
                                                spreadRadius: 2)
                                          ]),
                                      child: const Icon(Icons.local_shipping,
                                          color: Color(0xFFFFF8E1),
                                          size: 14))))),
                      Positioned(
                          top: 14,
                          left: 14,
                          right: 14,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.65),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Color(0x121A3A2A))),
                              child: Text(widget.route,
                                  style: const TextStyle(
                                      color: Color(0xFFFFF8E1),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2))),
                      Positioned(
                          bottom: 14,
                          left: 14,
                          right: 14,
                          child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.78),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Color(0x121A3A2A))),
                              child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    Column(children: [
                                      const Text("ETA",
                                          style: TextStyle(
                                              color: Color(0x601A3A2A),
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold)),
                                      Text(_fmtEta(_eta),
                                          style: const TextStyle(
                                              color: Color(0xFFFFF8E1),
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18))
                                    ]),
                                    Container(
                                        width: 1,
                                        height: 28,
                                        color: Color(0x241A3A2A)),
                                    Column(children: [
                                      const Text("Distance",
                                          style: TextStyle(
                                              color: Color(0x601A3A2A),
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                          widget.distanceKm > 0
                                              ? "${(widget.distanceKm * (1 - _prog)).toStringAsFixed(0)} km left"
                                              : "${(_prog * 100).toStringAsFixed(0)}%",
                                          style: const TextStyle(
                                              color: Colors.blueAccent,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15))
                                    ]),
                                    Container(
                                        width: 1,
                                        height: 28,
                                        color: Color(0x241A3A2A)),
                                    Column(children: [
                                      const Text("Status",
                                          style: TextStyle(
                                              color: Color(0x601A3A2A),
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                          _status.length > 14
                                              ? _status.substring(0, 14)
                                              : _status,
                                          style: const TextStyle(
                                              color: Color(0xFFFB8C00),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11))
                                    ]),
                                  ]))),
                    ]))),
            Expanded(
                flex: 2,
                child: Container(
                    color: const Color(0xFF000000),
                    child: Column(children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Journey Progress",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                              color: Color(0xFF000000))),
                                      Text(
                                          "${(_prog * 100).toStringAsFixed(1)}%",
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: Colors.blueAccent))
                                    ]),
                                const SizedBox(height: 8),
                                ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                        value: _prog,
                                        backgroundColor: Colors.grey[200],
                                        color: Colors.blueAccent,
                                        minHeight: 10)),
                              ])),
                      Expanded(
                          child: ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 18),
                              itemCount: _log.length,
                              itemBuilder: (_, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(children: [
                                    const Icon(Icons.fiber_manual_record,
                                        size: 8, color: Colors.blueAccent),
                                    const SizedBox(width: 8),
                                    Flexible(
                                        child: Text(_log[i],
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF000000),
                                                fontWeight: FontWeight.w500)))
                                  ])))),
                    ]))),
          ]),

          // Tab 2: Nearby Hospitals
          ListView(padding: const EdgeInsets.all(16), children: [
            Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  const Flexible(
                      child: Text(
                          "Locations based on route proximity. Tap to call.",
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)))
                ])),
            const Text("NEARBY HOSPITALS",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            ..._hospitals.map((h) => _emergencyCard(h)),
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("EMERGENCY HELPLINES",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.blueGrey,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: _callChip("Ambulance", "108", Colors.red)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _callChip("Police", "100", Colors.blue)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _callChip("Highway", "1033", Colors.teal)),
                      ]),
                    ])),
          ]),

          // Tab 3: SOS & Repair
          ListView(padding: const EdgeInsets.all(16), children: [
            Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: Colors.red, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.sos,
                      color: Color(0xFF000000), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text("EMERGENCY SOS",
                            style: TextStyle(
                                color: Color(0xFF000000),
                                fontWeight: FontWeight.w900,
                                fontSize: 16)),
                        const Text("Tap to call National Highway Helpline",
                            style: TextStyle(
                                color: Color(0x701C1917), fontSize: 12))
                      ])),
                  GestureDetector(
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                              content:
                                  Text("Calling 1033 - NHAI Emergency..."))),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: const Color(0xFF000000),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Text("CALL 1033",
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13))))
                ])),
            const Text("HELPLINES",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            ..._emergency.map((e) => _emergencyCard(e, isCall: true)),
            const SizedBox(height: 8),
            const Text("NEARBY REPAIR & TYRE SHOPS",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            ..._repair.map((r) => _emergencyCard(r, isCall: true)),
          ]),
        ]),
      );

  Widget _callChip(String label, String number, Color c) => GestureDetector(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: c,
            behavior: SnackBarBehavior.floating,
            content: Text("Calling $number..."))),
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text(number,
                  style: const TextStyle(
                      color: Color(0xFFFFF8E1),
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
              Text(label,
                  style:
                      const TextStyle(color: Color(0x701A3A2A), fontSize: 10))
            ])),
      );
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFFFF8E1).withOpacity(0.04)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final rp = Paint()
      ..color = const Color(0xFFFFF8E1).withOpacity(0.06)
      ..strokeWidth = 6;
    canvas.drawLine(const Offset(0, 80), Offset(size.width, 80), rp);
    canvas.drawLine(Offset(size.width * 0.35, 0),
        Offset(size.width * 0.35, size.height), rp);
    canvas.drawLine(
        Offset(size.width * 0.7, 0), Offset(size.width * 0.7, size.height), rp);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ================================================================
// DRIVER LEDGER SCREEN
// ================================================================
class DriverLedgerScreen extends StatefulWidget {
  final Driver driver;
  final VoidCallback onUpdate;
  const DriverLedgerScreen(
      {super.key, required this.driver, required this.onUpdate});
  @override
  State<DriverLedgerScreen> createState() => _DriverLedgerScreenState();
}

class _DriverLedgerScreenState extends State<DriverLedgerScreen> {
  void _addTx() {
    DriverTxType type = DriverTxType.salary;
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (c) => StatefulBuilder(
            builder: (ctx, setSt) => Container(
                  decoration: const BoxDecoration(
                      color: Color(0xFFFBF7F0),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28))),
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom,
                      left: 28,
                      right: 28,
                      top: 28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text("New Ledger Entry",
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF000000))),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<DriverTxType>(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        initialValue: type,
                        decoration: InputDecoration(
                            labelText: "Transaction Type",
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00), width: 2))),
                        items: DriverTxType.values
                            .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.name.toUpperCase(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))))
                            .toList(),
                        onChanged: (v) => setSt(() => type = v!)),
                    const SizedBox(height: 14),
                    TextField(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        controller: amtCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: "Amount (â‚¹)",
                            prefixIcon: const Icon(Icons.currency_rupee),
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00),
                                    width: 2)))),
                    const SizedBox(height: 12),
                    TextField(
                        style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        controller: noteCtrl,
                        decoration: InputDecoration(
                            labelText: "Notes",
                            filled: true,
                            fillColor: const Color(0xFFFFF8E1),
                            labelStyle: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            floatingLabelStyle: const TextStyle(
                                color: Color(0xFFFB8C00),
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFFB8C00))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFFB8C00),
                                    width: 2)))),
                    const SizedBox(height: 20),
                    SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF8E1),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            onPressed: () {
                              double amt = double.tryParse(amtCtrl.text) ?? 0;
                              if (type == DriverTxType.advance ||
                                  type == DriverTxType.penalty ||
                                  type == DriverTxType.fuel ||
                                  type == DriverTxType.deduction) {
                                amt = -amt;
                              }
                              setState(() {
                                widget.driver.transactions.insert(
                                    0,
                                    DriverTx(
                                        date:
                                            "${DateTime.now().day}/${DateTime.now().month}",
                                        type: type,
                                        amount: amt,
                                        note: noteCtrl.text));
                                widget.driver.balance += amt;
                              });
                              widget.onUpdate();
                              Navigator.pop(c);
                            },
                            child: const Text("Save Entry",
                                style: TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)))),
                    const SizedBox(height: 20),
                  ]),
                )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: const Color(0xFFFFF8E1),
            iconTheme: const IconThemeData(color: Color(0xFF000000)),
            title: Text(widget.driver.name,
                style: const TextStyle(
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.w900))),
        body: Column(children: [
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: const BoxDecoration(
                  color: Color(0xFF000000),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(32))),
              child: Column(children: [
                const Text("Outstanding Balance",
                    style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Text("â‚¹${widget.driver.balance.toStringAsFixed(0)}",
                    style: TextStyle(
                        color: widget.driver.balance >= 0
                            ? const Color(0xFFFB8C00)
                            : const Color(0xFFE53E3E),
                        fontSize: 44,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                    widget.driver.balance >= 0
                        ? "Owed to driver"
                        : "Driver owes company",
                    style: const TextStyle(
                        color: Color(0xFF000000), fontSize: 13)),
                if (widget.driver.monthlySalary > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                          "Monthly Salary: â‚¹${widget.driver.monthlySalary.toStringAsFixed(0)}",
                          style: const TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)))
                ],
              ])),
          Expanded(
              child: widget.driver.transactions.isEmpty
                  ? const Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(Icons.receipt_outlined,
                              size: 50, color: Colors.grey),
                          SizedBox(height: 10),
                          Text("No transactions",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold))
                        ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.driver.transactions.length,
                      itemBuilder: (_, i) {
                        final tx = widget.driver.transactions[i];
                        bool pos = tx.amount >= 0;
                        return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                                color: const Color(0xFF000000),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 8)
                                ]),
                            child: ListTile(
                                contentPadding: const EdgeInsets.all(14),
                                leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                        color: pos
                                            ? Colors.green[50]
                                            : Colors.red[50],
                                        shape: BoxShape.circle),
                                    child: Icon(pos ? Icons.arrow_downward : Icons.arrow_upward,
                                        color: pos ? Colors.green : Colors.red,
                                        size: 18)),
                                title: Text(tx.type.name.toUpperCase(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13)),
                                subtitle: Text("${tx.date}${tx.note.isNotEmpty ? ' â€¢ ${tx.note}' : ''}",
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 11)),
                                trailing: Text(
                                    "${pos ? '+' : ''}â‚¹${tx.amount.abs().toStringAsFixed(0)}",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: pos ? Colors.green : Colors.red))));
                      })),
        ]),
        floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFFFFF8E1),
            icon: const Icon(Icons.add, color: Color(0xFF000000)),
            label: const Text("Add Entry",
                style: TextStyle(
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.bold)),
            onPressed: _addTx),
      );
}

// ================================================================
// PIE CHART PAINTER
// ================================================================
// ================================================================
// BACKGROUND PAINTER â€” Route network art for splash/login
// ================================================================

class NativePieChartPainter extends CustomPainter {
  final double revenue, expense;
  const NativePieChartPainter({required this.revenue, required this.expense});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final total = revenue > 0 ? revenue : 1;
    final expAngle = (expense / total) * 2 * math.pi;
    // Background ring â€” warm sand
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = const Color(0xFFFB8C00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12);
    // Expense arc â€” terracotta
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        expAngle,
        false,
        Paint()
          ..color = const Color(0xFFE53E3E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round);
    // Profit arc â€” sage green
    final profitAngle = math.max(0.0, 2 * math.pi - expAngle);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2 + expAngle,
        profitAngle,
        false,
        Paint()
          ..color = const Color(0xFFFB8C00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_) => true;
}

// Alias for backward compatibility
class _SplashBgPainter extends _RouteBgPainter {}

class _RouteBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // â”€â”€ Glowing orbs â€” depth & atmosphere â”€â”€
    void orb(double cx, double cy, double r, Color c, double opacity) {
      final p = Paint()..style = PaintingStyle.fill;
      p.shader =
          RadialGradient(colors: [c.withOpacity(opacity), Colors.transparent])
              .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, p);
    }

    orb(w * 0.08, h * 0.12, 180, const Color(0xFFFB8C00), 0.15);
    orb(w * 0.92, h * 0.38, 220, const Color(0xFFFFA726), 0.12);
    orb(w * 0.45, h * 0.80, 160, const Color(0xFFFB8C00), 0.06);
    orb(w * 0.78, h * 0.08, 120, const Color(0xFFFFA726), 0.10);
    orb(w * 0.2, h * 0.65, 140, const Color(0xFFFB8C00), 0.10);

    // â”€â”€ Fine dot grid â”€â”€
    final dotP = Paint()
      ..color = const Color(0xFFFB8C00).withOpacity(0.06)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < w; x += 30) {
      for (double y = 0; y < h; y += 30) {
        canvas.drawCircle(Offset(x, y), 1.0, dotP);
      }
    }

    // â”€â”€ Glowing highway lines â”€â”€
    final roadGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFFF8E1).withOpacity(0.08);

    // Diagonal highway 1 â€” top-left to mid-right
    roadGlow.color = const Color(0xFFFB8C00).withOpacity(0.12);
    canvas.drawLine(Offset(0, h * 0.3), Offset(w, h * 0.55), roadGlow);
    road.color = const Color(0xFFFB8C00).withOpacity(0.06);
    canvas.drawLine(Offset(0, h * 0.3), Offset(w, h * 0.55), road);

    // Diagonal highway 2
    roadGlow.color = const Color(0xFFFFA726).withOpacity(0.10);
    canvas.drawLine(Offset(w * 0.2, 0), Offset(w * 0.85, h), roadGlow);
    road.color = const Color(0xFFFB8C00).withOpacity(0.04);
    canvas.drawLine(Offset(w * 0.2, 0), Offset(w * 0.85, h), road);

    // Curved route arc
    final arc = Path()
      ..moveTo(0, h * 0.7)
      ..cubicTo(w * 0.3, h * 0.4, w * 0.6, h * 0.8, w, h * 0.3);
    roadGlow.color = const Color(0xFFFB8C00).withOpacity(0.08);
    roadGlow.strokeWidth = 6;
    canvas.drawPath(arc, roadGlow);
    road.color = const Color(0xFFFB8C00).withOpacity(0.05);
    road.strokeWidth = 1.5;
    canvas.drawPath(arc, road);

    // Location pins glow
    void pin(double x, double y, Color c) {
      canvas.drawCircle(
          Offset(x, y),
          6,
          Paint()
            ..color = c.withOpacity(0.8)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          Offset(x, y),
          12,
          Paint()
            ..color = c.withOpacity(0.2)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          Offset(x, y),
          20,
          Paint()
            ..color = c.withOpacity(0.07)
            ..style = PaintingStyle.fill);
    }

    pin(w * 0.18, h * 0.32, const Color(0xFFFB8C00));
    pin(w * 0.82, h * 0.52, const Color(0xFFF87171));
    pin(w * 0.5, h * 0.18, const Color(0xFFFFA726));

    // Moving truck dots on highway
    for (int i = 0; i < 4; i++) {
      final t = (i / 4.0);
      final tx = w * 0.1 + w * 0.7 * t;
      final ty = h * 0.31 + (h * 0.55 - h * 0.31) * t;
      canvas.drawCircle(
          Offset(tx, ty),
          3,
          Paint()
            ..color = const Color(0xFFFFF8E1).withOpacity(0.25)
            ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
