// ============================================================
// ROUTE MASTER ERP v3.0 — ENHANCED BUILD
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ==========================================
// CONFIG
// ==========================================
class AppConfig {
  static const String appVersion = "3.0.0";
  static const String adminPin = "1234";
  // Developer mode: tap version badge 7× on splash → enter this password
  static const String developerPassword = "ROUTEDEV2024";
  // Insert Google Maps/Places API Key for real-time features
  static const String googleMapsApiKey = "";
  static const String kredxPartnerCode = "ROUTEMASTER_ERP";
  // Fuel price per litre (₹) — update as needed
  static const double defaultDieselPrice = 92.0;
}

// ==========================================
// ENUMS
// ==========================================
enum UserRole { visitor, verified, owner, driver, admin, developer }

enum BidStatus { pending, dispatched }

enum VehicleOwnership { self, market }

enum DriverTxType { advance, salary, penalty, fuel, bonus, deduction }

enum SubscriptionTier { free, pro, business }

enum KredXStatus {
  draft,
  submitted,
  underReview,
  approved,
  disbursed,
  rejected
}

enum TripStatus { active, completed, overdue }

enum AdjustmentType {
  penaltyDeduction,
  taxDeduction,
  bonus,
  shortageDeduction,
  damageDeduction,
  other
}

enum ExportFormat { tally, caAudit, gst, csv }

enum GstType { none, cgstSgst, igst }

// ==========================================
// INDIAN STATES DATA
// ==========================================
class IndiaData {
  static const List<String> states = [
    "Andhra Pradesh",
    "Arunachal Pradesh",
    "Assam",
    "Bihar",
    "Chhattisgarh",
    "Goa",
    "Gujarat",
    "Haryana",
    "Himachal Pradesh",
    "Jharkhand",
    "Karnataka",
    "Kerala",
    "Madhya Pradesh",
    "Maharashtra",
    "Manipur",
    "Meghalaya",
    "Mizoram",
    "Nagaland",
    "Odisha",
    "Punjab",
    "Rajasthan",
    "Sikkim",
    "Tamil Nadu",
    "Telangana",
    "Tripura",
    "Uttar Pradesh",
    "Uttarakhand",
    "West Bengal",
    "Andaman & Nicobar Islands",
    "Chandigarh",
    "Dadra & Nagar Haveli",
    "Daman & Diu",
    "Delhi",
    "Jammu & Kashmir",
    "Ladakh",
    "Lakshadweep",
    "Puducherry"
  ];

  static const Map<String, List<String>> majorCitiesByState = {
    "Gujarat": [
      "Ahmedabad",
      "Surat",
      "Vadodara",
      "Rajkot",
      "Gandhinagar",
      "Anand",
      "Bharuch",
      "Bharuch GIDC",
      "Dahej Port",
      "Hazira",
      "Mundra Port",
      "Kandla Port",
      "Morbi",
      "Bhavnagar",
      "Jamnagar",
      "Mehsana",
      "Valsad",
      "Navsari"
    ],
    "Maharashtra": [
      "Mumbai",
      "Pune",
      "Nagpur",
      "Nashik",
      "Aurangabad",
      "Solapur",
      "Thane",
      "Navi Mumbai",
      "Raigad",
      "JNPT",
      "Bhiwandi",
      "Kolhapur",
      "Ahmednagar"
    ],
    "Rajasthan": [
      "Jaipur",
      "Jodhpur",
      "Udaipur",
      "Kota",
      "Ajmer",
      "Bikaner",
      "Alwar",
      "Bhilwara"
    ],
    "Punjab": [
      "Amritsar",
      "Ludhiana",
      "Chandigarh",
      "Jalandhar",
      "Patiala",
      "Bathinda"
    ],
    "Haryana": [
      "Gurgaon",
      "Faridabad",
      "Panipat",
      "Ambala",
      "Hisar",
      "Rohtak",
      "Sonipat"
    ],
    "Delhi": [
      "New Delhi",
      "Delhi NCR",
      "Okhla",
      "Naraina",
      "Wazirpur",
      "Ghazipur"
    ],
    "Uttar Pradesh": [
      "Lucknow",
      "Kanpur",
      "Agra",
      "Varanasi",
      "Meerut",
      "Noida",
      "Ghaziabad",
      "Allahabad",
      "Mathura"
    ],
    "Madhya Pradesh": [
      "Bhopal",
      "Indore",
      "Jabalpur",
      "Gwalior",
      "Ujjain",
      "Ratlam",
      "Dewas"
    ],
    "Tamil Nadu": [
      "Chennai",
      "Coimbatore",
      "Madurai",
      "Tiruchirappalli",
      "Salem",
      "Tiruppur",
      "Thoothukudi"
    ],
    "Karnataka": [
      "Bengaluru",
      "Mysuru",
      "Mangaluru",
      "Hubli",
      "Belgaum",
      "Davangere"
    ],
    "Telangana": [
      "Hyderabad",
      "Warangal",
      "Karimnagar",
      "Nizamabad",
      "Khammam"
    ],
    "West Bengal": [
      "Kolkata",
      "Howrah",
      "Durgapur",
      "Asansol",
      "Siliguri",
      "Haldia Port"
    ],
    "Andhra Pradesh": [
      "Visakhapatnam",
      "Vijayawada",
      "Guntur",
      "Nellore",
      "Kakinada",
      "Tirupati"
    ],
  };

  static List<String> searchCities(String query) {
    if (query.length < 2) return [];
    final q = query.toLowerCase();
    List<String> results = [];
    majorCitiesByState.forEach((state, cities) {
      for (final city in cities) {
        if (city.toLowerCase().contains(q)) {
          results.add("$city, $state");
        }
      }
    });
    // Also match state names
    for (final state in states) {
      if (state.toLowerCase().contains(q) &&
          !results.any((r) => r.contains(state))) {
        results.add(state);
      }
    }
    return results.take(8).toList();
  }

  static String? extractState(String cityStateString) {
    if (cityStateString.contains(',')) {
      return cityStateString.split(',').last.trim();
    }
    if (states.contains(cityStateString.trim())) return cityStateString.trim();
    return null;
  }
}

// Fallback Indian Cities for CitySearchField when Maps API is empty
const List<Map<String, String>> kIndianCities = [
  {'city': 'Ahmedabad', 'state': 'Gujarat', 'full': 'Ahmedabad, Gujarat'},
  {'city': 'Surat', 'state': 'Gujarat', 'full': 'Surat, Gujarat'},
  {'city': 'Mumbai', 'state': 'Maharashtra', 'full': 'Mumbai, Maharashtra'},
  {'city': 'Delhi', 'state': 'Delhi', 'full': 'Delhi, NCR'},
  {'city': 'Bangalore', 'state': 'Karnataka', 'full': 'Bangalore, Karnataka'},
  {'city': 'Chennai', 'state': 'Tamil Nadu', 'full': 'Chennai, Tamil Nadu'},
  {'city': 'Hyderabad', 'state': 'Telangana', 'full': 'Hyderabad, Telangana'},
  {'city': 'Kolkata', 'state': 'West Bengal', 'full': 'Kolkata, West Bengal'},
  {'city': 'Pune', 'state': 'Maharashtra', 'full': 'Pune, Maharashtra'},
  {'city': 'Jaipur', 'state': 'Rajasthan', 'full': 'Jaipur, Rajasthan'},
];

class BankEntry {
  final String date;
  final String narration;
  final String refNo;
  final double debit;
  final double credit;
  bool isMatched;
  String? matchedLedgerId;

  BankEntry({
    required this.date,
    required this.narration,
    required this.refNo,
    required this.debit,
    required this.credit,
    this.isMatched = false,
    this.matchedLedgerId,
  });
}

// ==========================================
// MODELS
// ==========================================

class LedgerAdjustment {
  AdjustmentType type;
  double amount;
  String note;
  String date;
  bool isDeduction; // true = reduces amount owed to us / increases expense

  LedgerAdjustment({
    required this.type,
    required this.amount,
    required this.note,
    required this.date,
    required this.isDeduction,
  });

  String get typeLabel {
    switch (type) {
      case AdjustmentType.penaltyDeduction:
        return "Penalty Deduction";
      case AdjustmentType.taxDeduction:
        return "Tax Deducted at Source";
      case AdjustmentType.bonus:
        return "Bonus / Extra Payment";
      case AdjustmentType.shortageDeduction:
        return "Shortage / Shortage Claim";
      case AdjustmentType.damageDeduction:
        return "Damage Claim";
      case AdjustmentType.other:
        return "Other Adjustment";
    }
  }

  Color get color => isDeduction ? Colors.black : Colors.black;

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'amount': amount,
        'note': note,
        'date': date,
        'isDeduction': isDeduction
      };
  factory LedgerAdjustment.fromJson(Map<String, dynamic> j) => LedgerAdjustment(
        type: AdjustmentType.values[j['type'] ?? 0],
        amount: j['amount'] ?? 0,
        note: j['note'] ?? '',
        date: j['date'] ?? '',
        isDeduction: j['isDeduction'] ?? true,
      );
}

class BankTransaction {
  String date, description, ref;
  double credit, debit;
  bool isMatched;
  String? matchedTripId;
  String? matchedParty;

  BankTransaction({
    required this.date,
    required this.description,
    required this.ref,
    this.credit = 0,
    this.debit = 0,
    this.isMatched = false,
    this.matchedTripId,
    this.matchedParty,
  });

  double get amount => credit > 0 ? credit : -debit;
}

class DriverDocument {
  String type; // 'aadhaar', 'dl', 'photo'
  bool isUploaded;
  String fileName;
  String uploadDate;

  DriverDocument(
      {required this.type,
      this.isUploaded = false,
      this.fileName = '',
      this.uploadDate = ''});

  String get displayName {
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
        'uploadDate': uploadDate
      };
  factory DriverDocument.fromJson(Map<String, dynamic> j) => DriverDocument(
        type: j['type'] ?? '',
        isUploaded: j['isUploaded'] ?? false,
        fileName: j['fileName'] ?? '',
        uploadDate: j['uploadDate'] ?? '',
      );
}

class SubscriptionInfo {
  SubscriptionTier tier;
  String expiryDate;
  int tripsUsedThisMonth;

  SubscriptionInfo(
      {this.tier = SubscriptionTier.free,
      this.expiryDate = "",
      this.tripsUsedThisMonth = 0});

  int get maxTripsPerMonth => tier == SubscriptionTier.free ? 10 : 99999;
  bool get canExportPDF =>
      true; // Enabled for all for demo; in prod: tier != SubscriptionTier.free
  bool get canUseGPS => tier != SubscriptionTier.free;
  bool get canUseKredX => tier == SubscriptionTier.business;
  bool get hasAdvancedAnalytics => tier != SubscriptionTier.free;
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
    }
  }

  Color get tierColor {
    switch (tier) {
      case SubscriptionTier.free:
        return Colors.black;
      case SubscriptionTier.pro:
        return const Color(0xFF212121);
      case SubscriptionTier.business:
        return Colors.black[700]!;
    }
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.index,
        'expiryDate': expiryDate,
        'tripsUsedThisMonth': tripsUsedThisMonth
      };
  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) =>
      SubscriptionInfo(
        tier: SubscriptionTier.values[json['tier'] ?? 0],
        expiryDate: json['expiryDate'] ?? "",
        tripsUsedThisMonth: json['tripsUsedThisMonth'] ?? 0,
      );
}

class KredXApplication {
  String id, invoiceLedgerId, partyName;
  double invoiceAmount, requestedAmount, approvedAmount;
  KredXStatus status;
  String appliedDate;
  int tenureDays;
  double interestRate;

  KredXApplication({
    required this.id,
    required this.invoiceLedgerId,
    required this.partyName,
    required this.invoiceAmount,
    required this.requestedAmount,
    this.approvedAmount = 0,
    this.status = KredXStatus.draft,
    required this.appliedDate,
    this.tenureDays = 30,
    this.interestRate = 1.5,
  });

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
        return "Approved ✓";
      case KredXStatus.disbursed:
        return "Disbursed 💸";
      case KredXStatus.rejected:
        return "Rejected";
    }
  }

  Color get statusColor {
    switch (status) {
      case KredXStatus.draft:
        return Colors.black;
      case KredXStatus.submitted:
        return Colors.black;
      case KredXStatus.underReview:
        return Colors.black;
      case KredXStatus.approved:
        return Colors.black;
      case KredXStatus.disbursed:
        return Colors.black;
      case KredXStatus.rejected:
        return Colors.black;
    }
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
  factory KredXApplication.fromJson(Map<String, dynamic> json) =>
      KredXApplication(
        id: json['id'],
        invoiceLedgerId: json['invoiceLedgerId'],
        partyName: json['partyName'],
        invoiceAmount: json['invoiceAmount'],
        requestedAmount: json['requestedAmount'],
        approvedAmount: json['approvedAmount'] ?? 0,
        status: KredXStatus.values[json['status'] ?? 0],
        appliedDate: json['appliedDate'],
        tenureDays: json['tenureDays'] ?? 30,
        interestRate: json['interestRate'] ?? 1.5,
      );
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
  UserRole role;
  UserProfile({
    this.companyName = "Sandhu Logistics",
    this.gstin = "Unregistered",
    this.phone = "+91 0000000000",
    this.address = "Ahmedabad, Gujarat",
    this.email = "",
    this.bankName = "",
    this.bankAccount = "",
    this.bankIfsc = "",
    this.panNumber = "",
    this.role = UserRole.owner,
  });
  Map<String, dynamic> toJson() => {
        'companyName': companyName,
        'gstin': gstin,
        'phone': phone,
        'address': address,
        'email': email,
        'bankName': bankName,
        'bankAccount': bankAccount,
        'bankIfsc': bankIfsc,
        'panNumber': panNumber,
        'role': role.index,
      };
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        companyName: json['companyName'] ?? "",
        gstin: json['gstin'] ?? "",
        phone: json['phone'] ?? "",
        address: json['address'] ?? "",
        email: json['email'] ?? "",
        bankName: json['bankName'] ?? "",
        bankAccount: json['bankAccount'] ?? "",
        bankIfsc: json['bankIfsc'] ?? "",
        panNumber: json['panNumber'] ?? "",
        role: json.containsKey('role')
            ? UserRole.values[(json['role'] as int)]
            : UserRole.owner,
      );

  Null get pan => null;
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
  factory DriverTx.fromJson(Map<String, dynamic> json) => DriverTx(
      date: json['date'],
      type: DriverTxType.values[json['type']],
      amount: json['amount'],
      note: json['note']);
}

class Driver {
  String id, name, phone, aadharNum, dlNum;
  double balance, monthlySalary;
  bool hasSelfie;
  List<DriverTx> transactions;
  List<DriverDocument> documents;

  Driver({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    required this.transactions,
    this.aadharNum = "",
    this.dlNum = "",
    this.hasSelfie = false,
    this.monthlySalary = 0,
    List<DriverDocument>? documents,
  }) : documents = documents ??
            [
              DriverDocument(type: 'aadhaar'),
              DriverDocument(type: 'dl'),
              DriverDocument(type: 'photo'),
            ];

  bool get allDocumentsUploaded => documents.every((d) => d.isUploaded);
  int get uploadedDocCount => documents.where((d) => d.isUploaded).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'balance': balance,
        'aadharNum': aadharNum,
        'dlNum': dlNum,
        'hasSelfie': hasSelfie,
        'monthlySalary': monthlySalary,
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'documents': documents.map((d) => d.toJson()).toList(),
      };
  factory Driver.fromJson(Map<String, dynamic> json) => Driver(
        id: json['id'],
        name: json['name'],
        phone: json['phone'],
        balance: (json['balance'] as num).toDouble(),
        transactions: (json['transactions'] as List)
            .map((t) => DriverTx.fromJson(t))
            .toList(),
        aadharNum: json['aadharNum'] ?? "",
        dlNum: json['dlNum'] ?? "",
        hasSelfie: json['hasSelfie'] ?? false,
        monthlySalary: (json['monthlySalary'] as num?)?.toDouble() ?? 0,
        documents: json['documents'] != null
            ? (json['documents'] as List)
                .map((d) => DriverDocument.fromJson(d))
                .toList()
            : null,
      );
}

class TripLedger {
  String id, date, partyName, vehicleNo, route;
  VehicleOwnership ownership;
  String eWayBillNo, materialName;
  double freightBilled, paymentReceived;
  double diesel, toll, driverExp, materialLoss;
  double marketTruckFreight, marketAdvancePaid;
  String? driverName;
  String? driverId;
  int paymentTermsDays;
  String loadingPoint, unloadingPoint, loadingState, unloadingState;
  double distanceKm;
  double fuelEconomy;
  double dieselPricePerLitre;
  int vehicleAxles;
  String consignorPhone, consignorEmail;
  List<LedgerAdjustment> adjustments;
  bool documentsSentToConsignor;
  bool paymentNotificationSent;
  double grossWeight, tareWeight;
  String lrNumber;
  double tdsDeduction;
  double penalties;
  GstType gstType;
  double gstRate;
  bool isGstInclusive;
  double weightTons;
  String weightUnit;
  String lrNotes;
  String consignorGstin;

  TripLedger({
    required this.id,
    required this.date,
    required this.partyName,
    required this.vehicleNo,
    required this.route,
    required this.ownership,
    this.eWayBillNo = "PENDING",
    this.materialName = "General Goods",
    required this.freightBilled,
    this.paymentReceived = 0,
    this.diesel = 0,
    this.toll = 0,
    this.driverExp = 0,
    this.materialLoss = 0,
    this.marketTruckFreight = 0,
    this.marketAdvancePaid = 0,
    this.driverName,
    this.driverId,
    this.paymentTermsDays = 30,
    this.loadingPoint = "",
    this.unloadingPoint = "",
    this.loadingState = "",
    this.unloadingState = "",
    this.distanceKm = 0,
    this.fuelEconomy = 3.5,
    this.dieselPricePerLitre = 92.0,
    this.vehicleAxles = 6,
    this.consignorPhone = "",
    this.consignorEmail = "",
    List<LedgerAdjustment>? adjustments,
    this.documentsSentToConsignor = false,
    this.paymentNotificationSent = false,
    this.grossWeight = 0,
    this.tareWeight = 0,
    this.lrNumber = "",
    this.tdsDeduction = 0,
    this.penalties = 0,
    this.gstType = GstType.none,
    this.gstRate = 0,
    this.isGstInclusive = false,
    this.weightTons = 0,
    this.weightUnit = "MT",
    this.lrNotes = "",
    this.consignorGstin = "",
  }) : adjustments = adjustments ?? [];

  double get totalAdjustmentDeductions =>
      adjustments.where((a) => a.isDeduction).fold(0, (s, a) => s + a.amount);
  double get totalAdjustmentAdditions =>
      adjustments.where((a) => !a.isDeduction).fold(0, (s, a) => s + a.amount);
  double get netFreightBilled =>
      freightBilled - totalAdjustmentDeductions + totalAdjustmentAdditions;
  double get taxableFreight => isGstInclusive && gstRate > 0
      ? freightBilled / (1 + (gstRate / 100))
      : freightBilled;
  double get gstAmount => isGstInclusive && gstRate > 0
      ? freightBilled - taxableFreight
      : freightBilled * (gstRate / 100);
  double get selfExpenses => diesel + toll + driverExp + materialLoss;
  double get marketCommission =>
      freightBilled - marketTruckFreight - materialLoss;
  double get tripProfit => ownership == VehicleOwnership.self
      ? (netFreightBilled - selfExpenses)
      : marketCommission;
  double get partyPending => netFreightBilled - paymentReceived;
  bool get isOverdue => partyPending > 0;
  double get netPayload => grossWeight - tareWeight;
  DateTime? get paymentDueDate => dueDateObj;
  bool get isPaymentOverdue => isPaymentDue;

  DateTime? get dueDateObj {
    try {
      final parts = date.split('/');
      final d = DateTime(
          int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      return d.add(Duration(days: paymentTermsDays));
    } catch (_) {
      return null;
    }
  }

  bool get isPaymentDue {
    final due = dueDateObj;
    if (due == null) return false;
    return DateTime.now().isAfter(due) && partyPending > 0;
  }

  int get daysOverdue {
    final due = dueDateObj;
    if (due == null) return 0;
    return DateTime.now().difference(due).inDays;
  }

  TripStatus get status {
    if (partyPending <= 0) return TripStatus.completed;
    if (isOverdue) return TripStatus.overdue;
    return TripStatus.active;
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
        'freightBilled': freightBilled,
        'paymentReceived': paymentReceived,
        'diesel': diesel,
        'toll': toll,
        'driverExp': driverExp,
        'materialLoss': materialLoss,
        'marketTruckFreight': marketTruckFreight,
        'marketAdvancePaid': marketAdvancePaid,
        'driverName': driverName,
        'driverId': driverId,
        'paymentTermsDays': paymentTermsDays,
        'loadingPoint': loadingPoint,
        'unloadingPoint': unloadingPoint,
        'loadingState': loadingState,
        'unloadingState': unloadingState,
        'distanceKm': distanceKm,
        'fuelEconomy': fuelEconomy,
        'dieselPricePerLitre': dieselPricePerLitre,
        'vehicleAxles': vehicleAxles,
        'consignorPhone': consignorPhone,
        'consignorEmail': consignorEmail,
        'adjustments': adjustments.map((a) => a.toJson()).toList(),
        'documentsSentToConsignor': documentsSentToConsignor,
        'paymentNotificationSent': paymentNotificationSent,
        'grossWeight': grossWeight,
        'tareWeight': tareWeight,
        'lrNumber': lrNumber,
        'tdsDeduction': tdsDeduction,
        'penalties': penalties,
        'gstType': gstType.index,
        'gstRate': gstRate,
        'isGstInclusive': isGstInclusive,
        'weightTons': weightTons,
        'weightUnit': weightUnit,
        'lrNotes': lrNotes,
        'consignorGstin': consignorGstin,
      };

  factory TripLedger.fromJson(Map<String, dynamic> json) => TripLedger(
        id: json['id'] ?? "TRP${math.Random().nextInt(9999)}",
        date: json['date'] ?? "",
        partyName: json['partyName'] ?? "",
        vehicleNo: json['vehicleNo'] ?? "",
        route: json['route'] ?? "",
        ownership: json['ownership'] != null
            ? VehicleOwnership.values[json['ownership']]
            : VehicleOwnership.self,
        eWayBillNo: json['eWayBillNo'] ?? "PENDING",
        materialName: json['materialName'] ?? "General Goods",
        freightBilled: (json['freightBilled'] as num?)?.toDouble() ?? 0,
        paymentReceived: (json['paymentReceived'] as num?)?.toDouble() ?? 0,
        diesel: (json['diesel'] as num?)?.toDouble() ?? 0,
        toll: (json['toll'] as num?)?.toDouble() ?? 0,
        driverExp: (json['driverExp'] as num?)?.toDouble() ?? 0,
        materialLoss: (json['materialLoss'] as num?)?.toDouble() ?? 0,
        marketTruckFreight:
            (json['marketTruckFreight'] as num?)?.toDouble() ?? 0,
        marketAdvancePaid: (json['marketAdvancePaid'] as num?)?.toDouble() ?? 0,
        driverName: json['driverName'],
        driverId: json['driverId'],
        paymentTermsDays: json['paymentTermsDays'] ?? 30,
        loadingPoint: json['loadingPoint'] ?? "",
        unloadingPoint: json['unloadingPoint'] ?? "",
        loadingState: json['loadingState'] ?? "",
        unloadingState: json['unloadingState'] ?? "",
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        fuelEconomy: (json['fuelEconomy'] as num?)?.toDouble() ?? 3.5,
        dieselPricePerLitre:
            (json['dieselPricePerLitre'] as num?)?.toDouble() ?? 92.0,
        vehicleAxles: json['vehicleAxles'] ?? 6,
        consignorPhone: json['consignorPhone'] ?? "",
        consignorEmail: json['consignorEmail'] ?? "",
        adjustments: json['adjustments'] != null
            ? (json['adjustments'] as List)
                .map((a) => LedgerAdjustment.fromJson(a))
                .toList()
            : [],
        documentsSentToConsignor: json['documentsSentToConsignor'] ?? false,
        paymentNotificationSent: json['paymentNotificationSent'] ?? false,
        grossWeight: (json['grossWeight'] as num?)?.toDouble() ?? 0,
        tareWeight: (json['tareWeight'] as num?)?.toDouble() ?? 0,
        lrNumber: json['lrNumber'] ?? "",
        tdsDeduction: (json['tdsDeduction'] as num?)?.toDouble() ?? 0,
        penalties: (json['penalties'] as num?)?.toDouble() ?? 0,
        gstType: json['gstType'] != null
            ? GstType.values[json['gstType']]
            : GstType.none,
        gstRate: (json['gstRate'] as num?)?.toDouble() ?? 0,
        isGstInclusive: json['isGstInclusive'] ?? false,
        weightTons: (json['weightTons'] as num?)?.toDouble() ?? 0,
        weightUnit: json['weightUnit'] ?? "MT",
        lrNotes: json['lrNotes'] ?? "",
        consignorGstin: json['consignorGstin'] ?? "",
      );
}

class FleetDoc {
  String name;
  bool isUploaded;
  String expiryDate;
  FleetDoc(
      {required this.name,
      this.isUploaded = false,
      this.expiryDate = "Pending"});
  Map<String, dynamic> toJson() =>
      {'name': name, 'isUploaded': isUploaded, 'expiryDate': expiryDate};
  factory FleetDoc.fromJson(Map<String, dynamic> json) => FleetDoc(
      name: json['name'],
      isUploaded: json['isUploaded'] ?? false,
      expiryDate: json['expiryDate'] ?? "Pending");
}

class Battery {
  String make, serial;
  bool hasBill;
  Battery(this.make, this.serial, this.hasBill);
  Map<String, dynamic> toJson() =>
      {'make': make, 'serial': serial, 'hasBill': hasBill};
  factory Battery.fromJson(Map<String, dynamic> json) =>
      Battery(json['make'], json['serial'], json['hasBill']);
}

class Asset {
  String id, number, type, payload;
  int tyreCount;
  List<String> tyreSerials;
  List<Battery> batteries;
  List<FleetDoc> docs;
  int axleCount;
  String ownerName, ownerPhone;

  Asset({
    required this.id,
    required this.number,
    required this.type,
    required this.payload,
    required this.tyreCount,
    required this.tyreSerials,
    required this.batteries,
    required this.docs,
    this.axleCount = 6,
    this.ownerName = "",
    this.ownerPhone = "",
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'type': type,
        'payload': payload,
        'tyreCount': tyreCount,
        'tyreSerials': tyreSerials,
        'batteries': batteries.map((b) => b.toJson()).toList(),
        'docs': docs.map((d) => d.toJson()).toList(),
        'axleCount': axleCount,
        'ownerName': ownerName,
        'ownerPhone': ownerPhone,
      };
  factory Asset.fromJson(Map<String, dynamic> json) => Asset(
        id: json['id'],
        number: json['number'],
        type: json['type'],
        payload: json['payload'],
        tyreCount: json['tyreCount'],
        tyreSerials: List<String>.from(json['tyreSerials']),
        batteries: json['batteries'] != null
            ? (json['batteries'] as List)
                .map((b) => Battery.fromJson(b))
                .toList()
            : [],
        docs: json['docs'] != null
            ? (json['docs'] as List).map((d) => FleetDoc.fromJson(d)).toList()
            : [],
        axleCount: json['axleCount'] ?? 6,
        ownerName: json['ownerName'] ?? "",
        ownerPhone: json['ownerPhone'] ?? "",
      );
}

class MarketLoad {
  String id, route, details, vehicleType;
  double targetPrice;
  BidStatus status;
  String loadingState, unloadingState, loadingCity, unloadingCity;
  String materialType;
  double weightTons;
  String postedDate;

  MarketLoad({
    required this.id,
    required this.route,
    required this.details,
    required this.vehicleType,
    required this.targetPrice,
    this.status = BidStatus.pending,
    this.loadingState = "",
    this.unloadingState = "",
    this.loadingCity = "",
    this.unloadingCity = "",
    this.materialType = "",
    this.weightTons = 0,
    this.postedDate = "",
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'route': route,
        'details': details,
        'vehicleType': vehicleType,
        'targetPrice': targetPrice,
        'status': status.index,
        'loadingState': loadingState,
        'unloadingState': unloadingState,
        'loadingCity': loadingCity,
        'unloadingCity': unloadingCity,
        'materialType': materialType,
        'weightTons': weightTons,
        'postedDate': postedDate,
      };
  factory MarketLoad.fromJson(Map<String, dynamic> json) => MarketLoad(
        id: json['id'],
        route: json['route'],
        details: json['details'],
        vehicleType: json['vehicleType'],
        targetPrice: (json['targetPrice'] as num).toDouble(),
        status: BidStatus.values[json['status']],
        loadingState: json['loadingState'] ?? "",
        unloadingState: json['unloadingState'] ?? "",
        loadingCity: json['loadingCity'] ?? "",
        unloadingCity: json['unloadingCity'] ?? "",
        materialType: json['materialType'] ?? "",
        weightTons: (json['weightTons'] as num?)?.toDouble() ?? 0,
        postedDate: json['postedDate'] ?? "",
      );
}

// ==========================================
// GOOGLE MAPS / DISTANCE HELPER
// ==========================================
class RoutingEngine {
  static Future<Map<String, dynamic>> calculateRoute({
    required String origin,
    required String destination,
    int axles = 6,
    double fuelEconomy = 3.5,
    double dieselPrice = AppConfig.defaultDieselPrice,
  }) async {
    int km = 0;
    String source = "Smart Local Engine";

    if (AppConfig.googleMapsApiKey.isNotEmpty) {
      try {
        final enc = Uri.encodeComponent;
        final url = 'https://maps.googleapis.com/maps/api/distancematrix/json'
            '?origins=${enc(origin)}&destinations=${enc(destination)}'
            '&key=${AppConfig.googleMapsApiKey}&region=in&units=metric';
        final resp =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final meters =
              data['rows'][0]['elements'][0]['distance']['value'] as int;
          km = (meters / 1000).round();
          source = "Google Maps API";
        }
      } catch (_) {}
    }

    if (km == 0) {
      km =
          _smartDistanceLookup(origin.toLowerCase(), destination.toLowerCase());
      source = "Smart Local Engine";
    }

    double diesel = (km / fuelEconomy) * dieselPrice;
    // Toll: ₹2.0–2.5 per km per axle-pair (NHAI average for 4–6 axle)
    double tollPerKm = axles <= 2
        ? 1.2
        : axles <= 4
            ? 1.8
            : 2.2;
    double toll = km * tollPerKm;

    return {
      'km': km,
      'diesel': diesel.round(),
      'toll': toll.round(),
      'source': source,
      'axles': axles,
    };
  }

  static int _smartDistanceLookup(String o, String d) {
    final routes = <String, int>{
      'ahmedabad_mumbai': 530,
      'ahmedabad_delhi': 940,
      'ahmedabad_surat': 265,
      'ahmedabad_amritsar': 1150,
      'ahmedabad_pune': 660,
      'ahmedabad_jaipur': 680,
      'ahmedabad_indore': 590,
      'ahmedabad_nagpur': 870,
      'ahmedabad_hyderabad': 1050,
      'ahmedabad_bangalore': 1350,
      'ahmedabad_kolkata': 2020,
      'surat_mumbai': 290,
      'surat_delhi': 1200,
      'surat_pune': 390,
      'mumbai_delhi': 1420,
      'mumbai_bangalore': 990,
      'mumbai_hyderabad': 710,
      'mumbai_pune': 155,
      'mumbai_nagpur': 825,
      'delhi_jaipur': 270,
      'delhi_amritsar': 450,
      'delhi_lucknow': 550,
      'delhi_chandigarh': 250,
      'delhi_kolkata': 1500,
      'pune_bangalore': 840,
      'pune_hyderabad': 560,
      'bangalore_hyderabad': 570,
      'bangalore_chennai': 350,
      'hyderabad_chennai': 630,
      'hyderabad_kolkata': 1490,
      'kolkata_patna': 580,
      'kolkata_bhubaneswar': 440,
      'jaipur_amritsar': 500,
      'jaipur_jodhpur': 335,
      'bharuch_mumbai': 330,
      'bharuch_delhi': 900,
      'bharuch_surat': 80,
      'kandla_mumbai': 780,
      'kandla_delhi': 1200,
      'kandla_ahmedabad': 370,
      'hazira_mumbai': 320,
      'hazira_surat': 20,
      'hazira_ahmedabad': 280,
      'dahej_ahmedabad': 200,
      'dahej_surat': 150,
      'dahej_mumbai': 400,
    };

    String normalize(String s) => s
        .replaceAll(RegExp(r',.*'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^a-z]'), '');

    final a = normalize(o);
    final b = normalize(d);

    final key1 = '${a}_$b';
    final key2 = '${b}_$a';
    if (routes.containsKey(key1)) return routes[key1]!;
    if (routes.containsKey(key2)) return routes[key2]!;

    for (final entry in routes.entries) {
      final parts = entry.key.split('_');
      if ((parts[0].contains(a) || a.contains(parts[0])) &&
          (parts[1].contains(b) || b.contains(parts[1]))) {
        return entry.value;
      }
      if ((parts[1].contains(a) || a.contains(parts[1])) &&
          (parts[0].contains(b) || b.contains(parts[0]))) {
        return entry.value;
      }
    }

    return (a.length + b.length) * 35 + 200;
  }

  static Future<List<String>> getPlaceSuggestions(String query) async {
    if (query.length < 2) return [];

    if (AppConfig.googleMapsApiKey.isNotEmpty) {
      try {
        final enc = Uri.encodeComponent;
        final url =
            'https://maps.googleapis.com/maps/api/place/autocomplete/json'
            '?input=${enc(query)}&components=country:in&types=geocode'
            '&key=${AppConfig.googleMapsApiKey}';
        final resp =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final preds = data['predictions'] as List;
          return preds.map((p) => p['description'].toString()).take(6).toList();
        }
      } catch (_) {}
    }

    return IndiaData.searchCities(query);
  }
}

// ==========================================
// CSV / BANK STATEMENT PARSER
// ==========================================
class BankStatementParser {
  static List<BankTransaction> parseCSV(
      String csvContent, List<TripLedger> ledgers) {
    final lines = csvContent.split('\n');
    if (lines.isEmpty) return [];

    final transactions = <BankTransaction>[];

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = _splitCsv(line);
      if (cols.length < 3) continue;

      try {
        final tx = BankTransaction(
          date: cols[0].trim(),
          description: cols.length > 1 ? cols[1].trim() : '',
          ref: cols.length > 2 ? cols[2].trim() : '',
          debit: cols.length > 3
              ? (double.tryParse(cols[3].replaceAll(',', '').trim()) ?? 0)
              : 0,
          credit: cols.length > 4
              ? (double.tryParse(cols[4].replaceAll(',', '').trim()) ?? 0)
              : 0,
        );

        for (final ledger in ledgers) {
          if (_fuzzyMatch(tx.description, ledger.partyName)) {
            tx.isMatched = true;
            tx.matchedTripId = ledger.id;
            tx.matchedParty = ledger.partyName;
            break;
          }
        }

        transactions.add(tx);
      } catch (_) {}
    }

    return transactions;
  }

  static bool _fuzzyMatch(String bankDesc, String partyName) {
    final a = bankDesc.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final b = partyName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (a.isEmpty || b.isEmpty) return false;
    for (final word in b.split(RegExp(r'\s+'))) {
      if (word.length > 3 &&
          a.contains(word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))) {
        return true;
      }
    }
    return false;
  }

  static List<String> _splitCsv(String line) {
    final result = <String>[];
    bool inQuotes = false;
    final current = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      if (line[i] == '"') {
        inQuotes = !inQuotes;
      } else if (line[i] == ',' && !inQuotes) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(line[i]);
      }
    }
    result.add(current.toString());
    return result;
  }

  static String generateTallyExport(
      List<TripLedger> ledgers, UserProfile profile) {
    final sb = StringBuffer();
    sb.writeln(
        '"Voucher Type","Date","Voucher No","Party Name","Narration","Dr/Cr","Amount","Ledger"');

    for (final l in ledgers) {
      sb.writeln(
          '"Sales","${l.date}","${l.lrNumber.isNotEmpty ? l.lrNumber : l.id}","${l.partyName}",'
          '"Freight for ${l.materialName} - ${l.route}","Cr","${l.freightBilled.toStringAsFixed(2)}","Freight Income"');

      if (l.ownership == VehicleOwnership.self) {
        if (l.diesel > 0) {
          sb.writeln('"Payment","${l.date}","${l.id}","${l.vehicleNo}",'
              '"Diesel for ${l.route}","Dr","${l.diesel.toStringAsFixed(2)}","Diesel Expenses"');
        }
        if (l.toll > 0) {
          sb.writeln('"Payment","${l.date}","${l.id}","${l.vehicleNo}",'
              '"Toll/Fastag - ${l.route}","Dr","${l.toll.toStringAsFixed(2)}","Toll Expenses"');
        }
        if (l.driverExp > 0) {
          sb.writeln(
              '"Payment","${l.date}","${l.id}","${l.driverName ?? 'Driver'}",'
              '"Driver expenses - ${l.route}","Dr","${l.driverExp.toStringAsFixed(2)}","Driver Expenses"');
        }
      } else {
        sb.writeln('"Payment","${l.date}","${l.id}","Market Transporter",'
            '"Market truck freight - ${l.route}","Dr","${l.marketTruckFreight.toStringAsFixed(2)}","Market Truck Freight"');
      }

      for (final adj in l.adjustments) {
        sb.writeln('"Journal","${adj.date}","ADJ-${l.id}","${l.partyName}",'
            '"${adj.typeLabel} - ${adj.note}","${adj.isDeduction ? 'Dr' : 'Cr'}","${adj.amount.toStringAsFixed(2)}","${adj.typeLabel}"');
      }

      if (l.paymentReceived > 0) {
        sb.writeln('"Receipt","${l.date}","RCP-${l.id}","${l.partyName}",'
            '"Payment received for ${l.route}","Dr","${l.paymentReceived.toStringAsFixed(2)}","${l.partyName}"');
      }
    }

    return sb.toString();
  }

  static String generateCAAuditExport(
      List<TripLedger> ledgers, List<Driver> drivers, UserProfile profile) {
    final sb = StringBuffer();
    sb.writeln(
        '"COMPANY: ${profile.companyName} | GSTIN: ${profile.gstin} | PAN: ${profile.panNumber}"');
    sb.writeln(
        '"CA AUDIT EXPORT — Generated: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}"');
    sb.writeln('');
    sb.writeln('"=== TRIP LEDGER SUMMARY ==="');
    sb.writeln(
        '"Trip ID","Date","LR No","Party","Vehicle","Route","Material","E-Way Bill",'
        '"Freight Billed","Payment Received","Pending","Diesel","Toll","Driver Exp","Material Loss",'
        '"Market Freight","Profit/Commission","Adjustments","Net Profit","Status"');

    for (final l in ledgers) {
      final adj = l.totalAdjustmentDeductions - l.totalAdjustmentAdditions;
      final status = l.partyPending <= 0
          ? 'Cleared'
          : (l.isPaymentDue ? 'OVERDUE' : 'Pending');
      sb.writeln(
          '"${l.id}","${l.date}","${l.lrNumber.isNotEmpty ? l.lrNumber : 'N/A'}","${l.partyName}",'
          '"${l.vehicleNo}","${l.route}","${l.materialName}","${l.eWayBillNo}",'
          '"${l.freightBilled}","${l.paymentReceived}","${l.partyPending.toStringAsFixed(2)}",'
          '"${l.diesel}","${l.toll}","${l.driverExp}","${l.materialLoss}",'
          '"${l.marketTruckFreight}","${l.tripProfit.toStringAsFixed(2)}",'
          '"${adj.toStringAsFixed(2)}","${l.tripProfit.toStringAsFixed(2)}","$status"');
    }

    sb.writeln('');
    sb.writeln('"=== PARTY-WISE SUMMARY ==="');
    sb.writeln(
        '"Party Name","Total Billed","Total Received","Outstanding","Trips"');
    final partyMap = <String, Map<String, dynamic>>{};
    for (final l in ledgers) {
      partyMap.putIfAbsent(
          l.partyName, () => {'billed': 0.0, 'received': 0.0, 'trips': 0});
      partyMap[l.partyName]!['billed'] =
          (partyMap[l.partyName]!['billed'] as double) + l.freightBilled;
      partyMap[l.partyName]!['received'] =
          (partyMap[l.partyName]!['received'] as double) + l.paymentReceived;
      partyMap[l.partyName]!['trips'] =
          (partyMap[l.partyName]!['trips'] as int) + 1;
    }
    partyMap.forEach((party, data) {
      final billed = data['billed'] as double;
      final received = data['received'] as double;
      sb.writeln(
          '"$party","${billed.toStringAsFixed(2)}","${received.toStringAsFixed(2)}",'
          '"${(billed - received).toStringAsFixed(2)}","${data['trips']}"');
    });

    sb.writeln('');
    sb.writeln('"=== DRIVER LEDGER ==="');
    sb.writeln(
        '"Driver Name","Phone","Outstanding Balance","Total Advance","Total Salary","Trips"');
    for (final d in drivers) {
      final totalAdv = d.transactions
          .where((t) => t.type == DriverTxType.advance)
          .fold(0.0, (s, t) => s + t.amount.abs());
      final totalSal = d.transactions
          .where((t) => t.type == DriverTxType.salary)
          .fold(0.0, (s, t) => s + t.amount.abs());
      sb.writeln(
          '"${d.name}","${d.phone}","${d.balance.toStringAsFixed(2)}","${totalAdv.toStringAsFixed(2)}","${totalSal.toStringAsFixed(2)}","${d.transactions.length}"');
    }

    return sb.toString();
  }
}

// ==========================================
// CITY SEARCH FIELD UI
// ==========================================
class CitySearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String label;
  final IconData icon;
  final Color iconColor;
  final String initialValue;
  final Function(String city, String state) onCitySelected;

  const CitySearchField({
    super.key,
    this.controller,
    required this.label,
    required this.icon,
    required this.iconColor,
    this.initialValue = "",
    required this.onCitySelected,
  });

  @override
  State<CitySearchField> createState() => _CitySearchFieldState();
}

class _CitySearchFieldState extends State<CitySearchField> {
  late TextEditingController _ctrl;
  List<Map<String, String>> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    if (widget.initialValue.isNotEmpty && _ctrl.text.isEmpty) {
      _ctrl.text = widget.initialValue;
    }
    _ctrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final q = _ctrl.text.toLowerCase().trim();
      if (q.length < 2) {
        if (mounted) setState(() => _showSuggestions = false);
        return;
      }
      if (AppConfig.googleMapsApiKey.isNotEmpty) {
        _fetchPlacesFromAPI(q);
      } else {
        final filtered = kIndianCities
            .where((c) =>
                c['city']!.toLowerCase().contains(q) ||
                (c['state'] ?? '').toLowerCase().contains(q))
            .take(7)
            .toList();
        if (mounted) {
          setState(() {
            _suggestions = filtered;
            _showSuggestions = filtered.isNotEmpty;
          });
        }
      }
    });
  }

  Future<void> _fetchPlacesFromAPI(String query) async {
    try {
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(query)}'
          '&types=establishment|geocode'
          '&components=country:in'
          '&key=${AppConfig.googleMapsApiKey}');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final predictions = data['predictions'] as List? ?? [];
        if (mounted) {
          setState(() {
            _suggestions = predictions.take(7).map((p) {
              final desc = p['description'] as String? ?? '';
              final parts = desc.split(', ');
              return {
                'city': parts.isNotEmpty ? parts[0] : desc,
                'state': parts.length > 1 ? parts[1] : '',
                'full': desc,
                'place_id': p['place_id'] as String? ?? '',
              };
            }).toList();
            _showSuggestions = _suggestions.isNotEmpty;
          });
        }
      }
    } catch (_) {
      _onTextChanged();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon, color: widget.iconColor, size: 20),
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _ctrl.clear();
                      if (mounted) setState(() => _showSuggestions = false);
                    })
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFFFF8E1), width: 2)),
          ),
        ),
        if (_showSuggestions)
          Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEEEEEE))),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: const Color(0xFFF5F5F5)),
                itemBuilder: (ctx, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading:
                        Icon(widget.icon, color: widget.iconColor, size: 16),
                    title: Text(s['city'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: s['state'] != null && s['state']!.isNotEmpty
                        ? Text(s['full'] ?? s['state']!,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black))
                        : null,
                    onTap: () {
                      _ctrl.text = s['full'] ?? s['city'] ?? '';
                      widget.onCitySelected(s['city'] ?? '', s['state'] ?? '');
                      if (mounted) setState(() => _showSuggestions = false);
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

// ==========================================
// TRIP DETAIL SCREEN — Full Professional PDF
// ==========================================
class TripDetailScreen extends StatefulWidget {
  final TripLedger ledger;
  final UserProfile userProfile;
  final SubscriptionInfo subscription;
  final List<Driver> drivers;
  final Function(TripLedger) onUpdateLedger;
  final Function(KredXApplication) onKredXApply;

  const TripDetailScreen({
    super.key,
    required this.ledger,
    required this.userProfile,
    required this.subscription,
    required this.drivers,
    required this.onUpdateLedger,
    required this.onKredXApply,
  });

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late TripLedger _ledger;

  @override
  void initState() {
    super.initState();
    _ledger = widget.ledger;
  }

  Future<void> _generateAndShareLR() async {
    if (!widget.subscription.canExportPDF) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
          content: Text("PDF Export requires PRO or BUSINESS plan")));
      return;
    }
    final pdf = pw.Document();
    final userProfile = widget.userProfile;
    final l = _ledger;

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (pw.Context ctx) =>
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        // Header
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
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black)),
                      pw.SizedBox(height: 4),
                      pw.Text(userProfile.address,
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColor(0.7, 0.7, 0.8))),
                      pw.Text("Ph: ${userProfile.phone}",
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColor(0.7, 0.7, 0.8))),
                      if (userProfile.gstin.isNotEmpty &&
                          userProfile.gstin != "Unregistered")
                        pw.Text("GSTIN: ${userProfile.gstin}",
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColor(0.7, 0.7, 0.8))),
                    ]),
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: pw.BoxDecoration(
                            color: const PdfColor(0.23, 0.51, 0.96),
                            borderRadius: pw.BorderRadius.circular(6)),
                        child: pw.Text("LORRY RECEIPT",
                            style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black)),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text("LR No: LR-${l.id}",
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 11,
                              color: PdfColors.black)),
                      pw.Text("Date: ${l.date}",
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColor(0.7, 0.7, 0.8))),
                    ]),
              ]),
        ),
        pw.SizedBox(height: 18),

        // Route block
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
              color: const PdfColor(0.97, 0.97, 0.97),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: const PdfColor(0.88, 0.88, 0.88))),
          child: pw.Row(children: [
            pw.Expanded(
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                  pw.Text("FROM",
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColor(0.5, 0.5, 0.5))),
                  pw.Text(
                      l.loadingPoint.isNotEmpty
                          ? l.loadingPoint
                          : l.route.split('→').first.trim(),
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  if (l.loadingState.isNotEmpty)
                    pw.Text(l.loadingState,
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColor(0.4, 0.4, 0.4))),
                ])),
            pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 12),
                child: pw.Text("→",
                    style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor(0.23, 0.51, 0.96)))),
            pw.Expanded(
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                  pw.Text("TO",
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColor(0.5, 0.5, 0.5))),
                  pw.Text(
                      l.unloadingPoint.isNotEmpty
                          ? l.unloadingPoint
                          : l.route.split('→').last.trim(),
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.right),
                  if (l.unloadingState.isNotEmpty)
                    pw.Text(l.unloadingState,
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColor(0.4, 0.4, 0.4))),
                ])),
          ]),
        ),
        pw.SizedBox(height: 14),

        // Consignor + Vehicle details
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: const PdfColor(0.85, 0.85, 0.85))),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("CONSIGNOR / PARTY",
                      style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor(0.5, 0.5, 0.5))),
                  pw.SizedBox(height: 4),
                  pw.Text(l.partyName.toUpperCase(),
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  if (l.consignorGstin.isNotEmpty)
                    pw.Text("GSTIN: ${l.consignorGstin}",
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColor(0.4, 0.4, 0.4))),
                  if (l.consignorPhone.isNotEmpty)
                    pw.Text("Ph: ${l.consignorPhone}",
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColor(0.4, 0.4, 0.4))),
                  pw.SizedBox(height: 8),
                  pw.Text("PAYMENT TERMS: ${l.paymentTermsDays} DAYS",
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor(0.23, 0.51, 0.96))),
                ]),
          )),
          pw.SizedBox(width: 10),
          pw.Expanded(
              child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: const PdfColor(0.85, 0.85, 0.85))),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("VEHICLE & DISPATCH",
                      style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor(0.5, 0.5, 0.5))),
                  pw.SizedBox(height: 4),
                  _pdfRow("Vehicle No", l.vehicleNo),
                  if (l.driverName != null) _pdfRow("Driver", l.driverName!),
                  _pdfRow("Material", l.materialName),
                  if (l.weightTons > 0)
                    _pdfRow("Weight", "${l.weightTons} ${l.weightUnit}"),
                  _pdfRow("E-Way Bill", l.eWayBillNo),
                  if (l.distanceKm > 0)
                    _pdfRow(
                        "Distance", "${l.distanceKm.toStringAsFixed(0)} km"),
                ]),
          )),
        ]),
        pw.SizedBox(height: 14),

        // Freight table
        pw.Text("FREIGHT & CHARGES",
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor(0.5, 0.5, 0.5),
                letterSpacing: 1.5)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(
              color: const PdfColor(0.85, 0.85, 0.85), width: 0.8),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration:
                  const pw.BoxDecoration(color: PdfColor(0.05, 0.09, 0.16)),
              children: [
                _pdfCell("DESCRIPTION", isHeader: true),
                _pdfCell("AMOUNT (₹)",
                    isHeader: true, align: pw.TextAlign.right),
              ],
            ),
            pw.TableRow(children: [
              _pdfCell("Freight Charges — ${l.materialName}\n${l.route}"),
              _pdfCell(_fmt(l.freightBilled), align: pw.TextAlign.right),
            ]),
            if (l.paymentReceived > 0)
              pw.TableRow(children: [
                _pdfCell("Less: Advance / Amount Received"),
                _pdfCell("(${_fmt(l.paymentReceived)})",
                    align: pw.TextAlign.right,
                    color: const PdfColor(0.6, 0.1, 0.1)),
              ]),
            if (l.materialLoss > 0)
              pw.TableRow(children: [
                _pdfCell("Less: Material Shortage / Loss"),
                _pdfCell("(${_fmt(l.materialLoss)})",
                    align: pw.TextAlign.right,
                    color: const PdfColor(0.6, 0.1, 0.1)),
              ]),
            if (l.tdsDeduction > 0)
              pw.TableRow(children: [
                _pdfCell(
                    "Less: TDS Deducted (${l.tdsDeduction > 0 ? (l.tdsDeduction / l.freightBilled * 100).toStringAsFixed(1) : ''}%)"),
                _pdfCell("(${_fmt(l.tdsDeduction)})",
                    align: pw.TextAlign.right,
                    color: const PdfColor(0.6, 0.1, 0.1)),
              ]),
            if (l.penalties > 0)
              pw.TableRow(children: [
                _pdfCell("Less: Penalties / Deductions"),
                _pdfCell("(${_fmt(l.penalties)})",
                    align: pw.TextAlign.right,
                    color: const PdfColor(0.6, 0.1, 0.1)),
              ]),
            pw.TableRow(
              decoration:
                  const pw.BoxDecoration(color: PdfColor(0.93, 0.97, 1.0)),
              children: [
                _pdfCell("NET OUTSTANDING BALANCE", isBold: true),
                _pdfCell("₹ ${_fmt(l.partyPending)}",
                    align: pw.TextAlign.right,
                    isBold: true,
                    color: const PdfColor(0.0, 0.4, 0.0)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),

        // Notes
        if (l.lrNotes.isNotEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                color: const PdfColor(1.0, 0.97, 0.88),
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Text("Remarks: ${l.lrNotes}",
                style: const pw.TextStyle(fontSize: 9)),
          ),

        pw.Spacer(),

        // Footer
        pw.Divider(thickness: 0.8),
        pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("Terms & Conditions:",
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        "1. Subject to ${userProfile.address.split(',').last.trim()} jurisdiction.",
                        style: const pw.TextStyle(
                            fontSize: 7.5, color: PdfColor(0.4, 0.4, 0.4))),
                    pw.Text("2. Goods insured by consignor. Not our liability.",
                        style: const pw.TextStyle(
                            fontSize: 7.5, color: PdfColor(0.4, 0.4, 0.4))),
                    pw.Text("3. Interest @2% per month on overdue.",
                        style: const pw.TextStyle(
                            fontSize: 7.5, color: PdfColor(0.4, 0.4, 0.4))),
                    if (userProfile.bankAccount.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      pw.Text(
                          "Bank: ${userProfile.bankName}  A/c: ${userProfile.bankAccount}  IFSC: ${userProfile.bankIfsc}",
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColor(0.3, 0.3, 0.3))),
                    ],
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
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text(userProfile.companyName,
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColor(0.4, 0.4, 0.4))),
                  ]),
            ]),
        pw.SizedBox(height: 4),
        pw.Text("Generated by Route Master ERP • ${_ledger.date}",
            style: const pw.TextStyle(
                fontSize: 7, color: PdfColor(0.6, 0.6, 0.6))),
      ]),
    ));

    try {
      await Printing.sharePdf(
          bytes: await pdf.save(), filename: 'LR_${l.id}_${l.partyName}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("PDF Error: $e"), backgroundColor: Colors.black));
      }
    }
  }

  Future<void> _generateAndShareInvoice() async {
    if (!widget.subscription.canExportPDF) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
          content: Text("PDF Export requires PRO or BUSINESS plan")));
      return;
    }

    final pdf = pw.Document();
    final up = widget.userProfile;
    final l = _ledger;
    final invoiceNo = "INV-${l.id}";
    final cgst = l.gstType == GstType.cgstSgst ? l.gstAmount / 2 : 0.0;
    final sgst = l.gstType == GstType.cgstSgst ? l.gstAmount / 2 : 0.0;
    final igst = l.gstType == GstType.igst ? l.gstAmount : 0.0;

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (pw.Context ctx) =>
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        // Header
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
                            fontSize: 10, color: PdfColor(0.4, 0.4, 0.4))),
                    pw.Text("Tel: ${up.phone}",
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColor(0.4, 0.4, 0.4))),
                    if (up.gstin.isNotEmpty && up.gstin != "Unregistered")
                      pw.Text("GSTIN: ${up.gstin}",
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor(0.2, 0.2, 0.2))),
                    if (up.email.isNotEmpty)
                      pw.Text("Email: ${up.email}",
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColor(0.4, 0.4, 0.4))),
                  ]),
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: pw.BoxDecoration(
                          color: const PdfColor(0.05, 0.09, 0.16),
                          borderRadius: pw.BorderRadius.circular(6)),
                      child: pw.Text("TAX INVOICE",
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black)),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text("Invoice No: $invoiceNo",
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text("Date: ${l.date}",
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColor(0.4, 0.4, 0.4))),
                    pw.Text("Payment Due: ${l.paymentTermsDays} Days",
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColor(0.4, 0.4, 0.4))),
                  ]),
            ]),
        pw.SizedBox(height: 16),
        pw.Divider(color: const PdfColor(0.05, 0.09, 0.16), thickness: 1.5),
        pw.SizedBox(height: 14),

        // Bill To
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text("BILL TO:",
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor(0.5, 0.5, 0.5))),
                pw.SizedBox(height: 4),
                pw.Text(l.partyName.toUpperCase(),
                    style: pw.TextStyle(
                        fontSize: 15, fontWeight: pw.FontWeight.bold)),
                if (l.consignorGstin.isNotEmpty)
                  pw.Text("GSTIN: ${l.consignorGstin}",
                      style: const pw.TextStyle(fontSize: 10)),
                if (l.consignorPhone.isNotEmpty)
                  pw.Text("Ph: ${l.consignorPhone}",
                      style: const pw.TextStyle(fontSize: 10)),
              ])),
          pw.SizedBox(width: 20),
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text("SHIPMENT DETAILS:",
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor(0.5, 0.5, 0.5))),
                pw.SizedBox(height: 4),
                _pdfRow2("Route",
                    "${l.loadingPoint.isNotEmpty ? l.loadingPoint : ''} → ${l.unloadingPoint.isNotEmpty ? l.unloadingPoint : l.route.split('→').last.trim()}"),
                _pdfRow2("Vehicle No", l.vehicleNo),
                _pdfRow2("Material", l.materialName),
                if (l.weightTons > 0)
                  _pdfRow2("Weight", "${l.weightTons} ${l.weightUnit}"),
                _pdfRow2("E-Way Bill", l.eWayBillNo),
                if (l.driverName != null) _pdfRow2("Driver", l.driverName!),
              ])),
        ]),
        pw.SizedBox(height: 16),

        // Invoice table
        pw.Table(
          border: pw.TableBorder.all(
              color: const PdfColor(0.85, 0.85, 0.85), width: 0.8),
          columnWidths: {
            0: const pw.FixedColumnWidth(30),
            1: const pw.FlexColumnWidth(5),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration:
                  const pw.BoxDecoration(color: PdfColor(0.05, 0.09, 0.16)),
              children: [
                _pdfCell("#", isHeader: true, align: pw.TextAlign.center),
                _pdfCell("DESCRIPTION", isHeader: true),
                _pdfCell("AMOUNT (₹)",
                    isHeader: true, align: pw.TextAlign.right),
              ],
            ),
            pw.TableRow(children: [
              _pdfCell("1", align: pw.TextAlign.center),
              _pdfCell(
                  "Freight Charges for Transportation of ${l.materialName}\nRoute: ${l.route}\nVehicle: ${l.vehicleNo}${l.weightTons > 0 ? ' | Weight: ${l.weightTons} ${l.weightUnit}' : ''}"),
              _pdfCell(_fmt(l.taxableFreight), align: pw.TextAlign.right),
            ]),
            if (l.gstType != GstType.none) ...[
              if (l.gstType == GstType.cgstSgst) ...[
                pw.TableRow(children: [
                  _pdfCell("", align: pw.TextAlign.center),
                  _pdfCell("CGST @ ${l.gstRate / 2}%"),
                  _pdfCell(_fmt(cgst), align: pw.TextAlign.right),
                ]),
                pw.TableRow(children: [
                  _pdfCell("", align: pw.TextAlign.center),
                  _pdfCell("SGST @ ${l.gstRate / 2}%"),
                  _pdfCell(_fmt(sgst), align: pw.TextAlign.right),
                ]),
              ],
              if (l.gstType == GstType.igst)
                pw.TableRow(children: [
                  _pdfCell("", align: pw.TextAlign.center),
                  _pdfCell("IGST @ ${l.gstRate}%"),
                  _pdfCell(_fmt(igst), align: pw.TextAlign.right),
                ]),
            ],
            if (l.materialLoss > 0)
              pw.TableRow(children: [
                _pdfCell("", align: pw.TextAlign.center),
                _pdfCell("Less: Material Loss / Shortage Deduction"),
                _pdfCell("(${_fmt(l.materialLoss)})",
                    align: pw.TextAlign.right,
                    color: const PdfColor(0.7, 0.1, 0.1)),
              ]),
            if (l.tdsDeduction > 0)
              pw.TableRow(children: [
                _pdfCell("", align: pw.TextAlign.center),
                _pdfCell("Less: TDS Deducted"),
                _pdfCell("(${_fmt(l.tdsDeduction)})",
                    align: pw.TextAlign.right,
                    color: const PdfColor(0.7, 0.1, 0.1)),
              ]),
            if (l.penalties > 0)
              pw.TableRow(children: [
                _pdfCell("", align: pw.TextAlign.center),
                _pdfCell("Less: Penalties"),
                _pdfCell("(${_fmt(l.penalties)})",
                    align: pw.TextAlign.right,
                    color: const PdfColor(0.7, 0.1, 0.1)),
              ]),
            pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColor(0.93, 0.97, 1.0)),
                children: [
                  _pdfCell("", align: pw.TextAlign.center),
                  _pdfCell("TOTAL INVOICE AMOUNT", isBold: true),
                  _pdfCell(_fmt(l.freightBilled + l.gstAmount),
                      align: pw.TextAlign.right, isBold: true),
                ]),
            if (l.paymentReceived > 0)
              pw.TableRow(children: [
                _pdfCell("", align: pw.TextAlign.center),
                _pdfCell("Less: Advance Received"),
                _pdfCell("(${_fmt(l.paymentReceived)})",
                    align: pw.TextAlign.right),
              ]),
            pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColor(0.88, 0.97, 0.88)),
                children: [
                  _pdfCell("", align: pw.TextAlign.center),
                  _pdfCell("NET AMOUNT DUE", isBold: true),
                  _pdfCell("₹ ${_fmt(l.partyPending)}",
                      align: pw.TextAlign.right,
                      isBold: true,
                      color: const PdfColor(0.0, 0.4, 0.0)),
                ]),
          ],
        ),
        pw.SizedBox(height: 10),

        // Bank details for payment
        if (up.bankAccount.isNotEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                color: const PdfColor(0.97, 0.97, 0.97),
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("PAYMENT DETAILS",
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor(0.5, 0.5, 0.5))),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Text("Bank: ",
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text(up.bankName,
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(width: 20),
                    pw.Text("A/c: ",
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text(up.bankAccount,
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(width: 20),
                    pw.Text("IFSC: ",
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text(up.bankIfsc,
                        style: const pw.TextStyle(fontSize: 9)),
                  ]),
                ]),
          ),

        if (l.lrNotes.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text("Notes: ${l.lrNotes}",
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColor(0.4, 0.4, 0.4))),
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
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        "We declare that this invoice shows the actual price of services described.",
                        style: const pw.TextStyle(
                            fontSize: 7.5, color: PdfColor(0.4, 0.4, 0.4))),
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
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text(up.companyName,
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColor(0.4, 0.4, 0.4))),
                  ]),
            ]),
      ]),
    ));

    try {
      await Printing.sharePdf(
          bytes: await pdf.save(),
          filename: 'Invoice_${invoiceNo}_${l.partyName}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("PDF Error: $e"), backgroundColor: Colors.black));
      }
    }
  }

  String _fmt(double val) => val.toStringAsFixed(2);

  pw.Widget _pdfCell(String text,
      {bool isHeader = false,
      bool isBold = false,
      pw.TextAlign? align,
      PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 10,
          fontWeight:
              isHeader || isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader
              ? PdfColors.black
              : (color ?? const PdfColor(0.15, 0.15, 0.15)),
        ),
      ),
    );
  }

  pw.Widget _pdfRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColor(0.5, 0.5, 0.5))),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ]),
      );

  pw.Widget _pdfRow2(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(children: [
          pw.Text("$label: ",
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor(0.4, 0.4, 0.4))),
          pw.Flexible(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 9))),
        ]),
      );

  void _showAddPaymentSheet() {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String txType = "Payment";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("Add to Ledger — ${_ledger.partyName}",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: txType,
              decoration: InputDecoration(
                  labelText: "Entry Type",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12))),
              items: [
                "Payment Received",
                "Penalty Deducted",
                "TDS Deducted",
                "Short Landing Claim",
                "Other Deduction"
              ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setSt(() => txType = v!),
            ),
            const SizedBox(height: 14),
            TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: "Amount (₹)",
                    prefixIcon: const Icon(Icons.currency_rupee),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                    labelText: "Notes / Reference",
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)))),
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
                  if (amt <= 0) return;
                  final updated = TripLedger(
                    id: _ledger.id,
                    date: _ledger.date,
                    partyName: _ledger.partyName,
                    vehicleNo: _ledger.vehicleNo,
                    route: _ledger.route,
                    ownership: _ledger.ownership,
                    eWayBillNo: _ledger.eWayBillNo,
                    materialName: _ledger.materialName,
                    loadingPoint: _ledger.loadingPoint,
                    unloadingPoint: _ledger.unloadingPoint,
                    loadingState: _ledger.loadingState,
                    unloadingState: _ledger.unloadingState,
                    consignorPhone: _ledger.consignorPhone,
                    consignorEmail: _ledger.consignorEmail,
                    consignorGstin: _ledger.consignorGstin,
                    freightBilled: _ledger.freightBilled,
                    paymentReceived: txType == "Payment Received"
                        ? _ledger.paymentReceived + amt
                        : _ledger.paymentReceived,
                    diesel: _ledger.diesel,
                    toll: _ledger.toll,
                    driverExp: _ledger.driverExp,
                    materialLoss: txType == "Short Landing Claim"
                        ? _ledger.materialLoss + amt
                        : _ledger.materialLoss,
                    marketTruckFreight: _ledger.marketTruckFreight,
                    marketAdvancePaid: _ledger.marketAdvancePaid,
                    penalties: txType == "Penalty Deducted" ||
                            txType == "Other Deduction"
                        ? _ledger.penalties + amt
                        : _ledger.penalties,
                    tdsDeduction: txType == "TDS Deducted"
                        ? _ledger.tdsDeduction + amt
                        : _ledger.tdsDeduction,
                    distanceKm: _ledger.distanceKm,
                    fuelEconomy: _ledger.fuelEconomy,
                    driverName: _ledger.driverName,
                    paymentTermsDays: _ledger.paymentTermsDays,
                    lrNotes: _ledger.lrNotes.isNotEmpty
                        ? "${_ledger.lrNotes}\n$txType: ₹${amt.toStringAsFixed(0)} — ${noteCtrl.text}"
                        : "$txType: ₹${amt.toStringAsFixed(0)} — ${noteCtrl.text}",
                    gstType: _ledger.gstType,
                    gstRate: _ledger.gstRate,
                    isGstInclusive: _ledger.isGstInclusive,
                    weightTons: _ledger.weightTons,
                    weightUnit: _ledger.weightUnit,
                  );
                  setState(() => _ledger = updated);
                  widget.onUpdateLedger(updated);
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: Colors.black,
                      behavior: SnackBarBehavior.floating,
                      content: Text(
                          "✅ $txType of ₹${amt.toStringAsFixed(0)} recorded")));
                },
                child: const Text("Save Entry",
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _ledger;
    bool isSelf = l.ownership == VehicleOwnership.self;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8E1),
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(l.partyName,
            style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.black),
            tooltip: "Add Payment / Deduction",
            onPressed: _showAddPaymentSheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Header card
          _card(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l.date,
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      Row(children: [
                        Chip(
                            label: Text(isSelf ? "SELF FLEET" : "MARKET TRUCK",
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black)),
                            backgroundColor:
                                isSelf ? const Color(0xFF212121) : Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 4)),
                      ]),
                    ]),
                const SizedBox(height: 8),
                Text(l.partyName,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFF8E1))),
                Text(l.vehicleNo,
                    style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.black[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEEEEEE))),
                  child: Column(children: [
                    _infoRow(Icons.route, "Route", l.route),
                    if (l.loadingPoint.isNotEmpty)
                      _infoRow(Icons.trip_origin, "Loading",
                          "${l.loadingPoint}${l.loadingState.isNotEmpty ? ', ${l.loadingState}' : ''}"),
                    if (l.unloadingPoint.isNotEmpty)
                      _infoRow(Icons.location_on, "Unloading",
                          "${l.unloadingPoint}${l.unloadingState.isNotEmpty ? ', ${l.unloadingState}' : ''}"),
                    _infoRow(Icons.science, "Material", l.materialName),
                    if (l.weightTons > 0)
                      _infoRow(Icons.scale, "Weight",
                          "${l.weightTons} ${l.weightUnit}"),
                    _infoRow(Icons.receipt, "E-Way Bill", l.eWayBillNo),
                    if (l.driverName != null)
                      _infoRow(Icons.person, "Driver", l.driverName!),
                    if (l.distanceKm > 0)
                      _infoRow(Icons.map, "Distance",
                          "${l.distanceKm.toStringAsFixed(0)} km"),
                  ]),
                ),
                const SizedBox(height: 16),

                // Action buttons
                Row(children: [
                  Expanded(
                      child: _actionButton(
                          Icons.picture_as_pdf,
                          "Lorry Receipt",
                          const Color(0xFFFFF8E1),
                          _generateAndShareLR)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _actionButton(Icons.receipt_long, "Tax Invoice",
                          Colors.black, _generateAndShareInvoice)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _actionButton(Icons.add_circle, "Add Entry",
                          Colors.black, _showAddPaymentSheet)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _actionButton(
                          Icons.satellite_alt, "Track Live", Colors.black, () {
                    if (!widget.subscription.canUseGPS) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("GPS Tracking requires PRO plan"),
                          backgroundColor: Colors.black));
                      return;
                    }
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => LiveTrackingScreen(
                                route: l.route, vehicleNo: l.vehicleNo)));
                  })),
                ]),
              ])),
          const SizedBox(height: 16),

          // Financial card
          _card(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("FINANCIAL BREAKDOWN",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                              letterSpacing: 1.2)),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: l.partyPending <= 0
                                  ? Colors.black.withValues(alpha: 0.1)
                                  : l.isPaymentOverdue
                                      ? Colors.black.withValues(alpha: 0.1)
                                      : Colors.black.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(
                              l.partyPending <= 0
                                  ? "SETTLED"
                                  : l.isPaymentOverdue
                                      ? "OVERDUE"
                                      : "OUTSTANDING",
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: l.partyPending <= 0
                                      ? Colors.black
                                      : l.isPaymentOverdue
                                          ? Colors.black
                                          : Colors.black))),
                    ]),
                const SizedBox(height: 16),
                _finRow("Freight Billed", l.freightBilled, isBold: true),
                if (l.gstAmount > 0)
                  _finRow(
                      l.gstType == GstType.igst
                          ? "IGST @${l.gstRate}%"
                          : "GST @${l.gstRate}%",
                      l.gstAmount,
                      c: Colors.black),
                _finRow("Advance Received", l.paymentReceived, c: Colors.black),
                const Divider(height: 18),
                if (isSelf) ...[
                  _finRow("Diesel Fuel", l.diesel, c: Colors.deepOrange),
                  _finRow("Toll / FASTag", l.toll, c: Colors.black),
                  _finRow("Driver Expenses", l.driverExp, c: Colors.black),
                  if (l.materialLoss > 0)
                    _finRow("Material Loss", l.materialLoss,
                        c: Colors.black[900]!),
                ] else ...[
                  _finRow("Market Truck Freight", l.marketTruckFreight,
                      c: Colors.black),
                  _finRow("Advance Paid to Market", l.marketAdvancePaid,
                      c: Colors.black),
                ],
                if (l.tdsDeduction > 0)
                  _finRow("TDS Deducted", l.tdsDeduction, c: Colors.brown),
                if (l.penalties > 0)
                  _finRow("Penalties / Deductions", l.penalties,
                      c: Colors.deepOrange),
                const Divider(height: 18),
                if (l.partyPending > 0)
                  Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: l.isPaymentOverdue
                              ? Colors.black[50]
                              : Colors.black[50],
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                l.isPaymentOverdue
                                    ? "OVERDUE BALANCE"
                                    : "PENDING BALANCE",
                                style: TextStyle(
                                    color: l.isPaymentOverdue
                                        ? Colors.black
                                        : Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13)),
                            Text("₹${l.partyPending.toStringAsFixed(0)}",
                                style: TextStyle(
                                    color: l.isPaymentOverdue
                                        ? Colors.black
                                        : Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22)),
                          ])),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isSelf ? "NET PROFIT" : "NET COMMISSION",
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFF8E1))),
                      Text("₹${l.tripProfit.toStringAsFixed(0)}",
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF212121))),
                    ]),
                if (l.paymentDueDate != null) ...[
                  const SizedBox(height: 10),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.black[100],
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today,
                            size: 12, color: Colors.black),
                        const SizedBox(width: 6),
                        Text(
                            "Payment due: ${l.paymentDueDate!.day}/${l.paymentDueDate!.month}/${l.paymentDueDate!.year}",
                            style: TextStyle(
                                fontSize: 11,
                                color: l.isPaymentOverdue
                                    ? Colors.black
                                    : Colors.black,
                                fontWeight: FontWeight.w600)),
                      ])),
                ],
              ])),
        ]),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)
            ]),
        child: child,
      );

  Widget _actionButton(
          IconData icon, String label, Color c, VoidCallback onTap) =>
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: c,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 14, color: Colors.black),
          const SizedBox(width: 8),
          Text("$label: ",
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _finRow(String label, double val,
          {Color c = Colors.black87, bool isBold = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label,
                style: TextStyle(
                    fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
                    fontSize: isBold ? 14 : 13,
                    color: Colors.black87)),
            Text("₹${val.toStringAsFixed(0)}",
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: c,
                    fontSize: isBold ? 14 : 13)),
          ]));
}

// ==========================================
// TALLY / CA EXPORT SCREEN
// ==========================================
class TallyExportScreen extends StatefulWidget {
  final List<TripLedger> ledgers;
  final UserProfile userProfile;
  const TallyExportScreen(
      {super.key, required this.ledgers, required this.userProfile});
  @override
  State<TallyExportScreen> createState() => _TallyExportScreenState();
}

class _TallyExportScreenState extends State<TallyExportScreen> {
  String _selectedFormat = "Tally XML";
  String? _generatedData;

  String _buildTallyXML() {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln('<ENVELOPE>');
    sb.writeln('  <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>');
    sb.writeln('  <BODY><IMPORTDATA><REQUESTDESC>');
    sb.writeln('    <REPORTNAME>Vouchers</REPORTNAME>');
    sb.writeln(
        '    <STATICVARIABLES><SVCURRENTCOMPANY>${widget.userProfile.companyName}</SVCURRENTCOMPANY></STATICVARIABLES>');
    sb.writeln('  </REQUESTDESC><REQUESTDATA>');
    for (final l in widget.ledgers) {
      sb.writeln('  <TALLYMESSAGE><VOUCHER VCHTYPE="Sales" ACTION="Create">');
      sb.writeln('    <DATE>${l.date.replaceAll('/', '')}</DATE>');
      sb.writeln(
          '    <NARRATION>Freight - ${l.materialName} - ${l.route} - ${l.vehicleNo} - EWB:${l.eWayBillNo}</NARRATION>');
      sb.writeln('    <VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>');
      sb.writeln('    <PARTYLEDGERNAME>${l.partyName}</PARTYLEDGERNAME>');
      sb.writeln('    <ALLLEDGERENTRIES.LIST>');
      sb.writeln('      <LEDGERNAME>${l.partyName}</LEDGERNAME>');
      sb.writeln('      <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      sb.writeln(
          '      <AMOUNT>-${l.freightBilled.toStringAsFixed(2)}</AMOUNT>');
      sb.writeln('    </ALLLEDGERENTRIES.LIST>');
      sb.writeln('    <ALLLEDGERENTRIES.LIST>');
      sb.writeln('      <LEDGERNAME>Freight Income</LEDGERNAME>');
      sb.writeln('      <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      sb.writeln(
          '      <AMOUNT>${l.freightBilled.toStringAsFixed(2)}</AMOUNT>');
      sb.writeln('    </ALLLEDGERENTRIES.LIST>');
      sb.writeln('  </VOUCHER></TALLYMESSAGE>');
    }
    sb.writeln('  </REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>');
    return sb.toString();
  }

  String _buildCSV() {
    final sb = StringBuffer();
    sb.writeln(
        "Trip ID,Date,Party Name,Vehicle No,Route,Material,E-Way Bill,Loading Point,Unloading Point,"
        "Freight Billed,Payment Received,Pending,Diesel,Toll,Driver Exp,Material Loss,"
        "Penalties,TDS,Net Profit,GST Type,GST Amount,Weight,Payment Terms Days");
    for (final l in widget.ledgers) {
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
        l.tripProfit.toStringAsFixed(2),
        l.gstType.name,
        l.gstAmount.toStringAsFixed(2),
        "${l.weightTons} ${l.weightUnit}",
        l.paymentTermsDays,
      ].join(','));
    }
    return sb.toString();
  }

  String _buildPartyAgingReport() {
    final Map<String, double> partyBalance = {};
    for (final l in widget.ledgers) {
      partyBalance[l.partyName] =
          (partyBalance[l.partyName] ?? 0) + l.partyPending;
    }
    final sb = StringBuffer();
    sb.writeln("Party Aging Report — ${widget.userProfile.companyName}");
    sb.writeln(
        "Generated: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}");
    sb.writeln("---");
    sb.writeln("Party Name,Outstanding Amount,Overdue Trips");
    for (final entry in partyBalance.entries) {
      final overdue = widget.ledgers
          .where((l) => l.partyName == entry.key && l.isPaymentOverdue)
          .length;
      sb.writeln('"${entry.key}",${entry.value.toStringAsFixed(2)},$overdue');
    }
    return sb.toString();
  }

  void _generate() {
    String data;
    if (_selectedFormat == "Tally XML") {
      data = _buildTallyXML();
    } else if (_selectedFormat == "CA Audit CSV") {
      data = _buildCSV();
    } else {
      data = _buildPartyAgingReport();
    }
    setState(() => _generatedData = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8E1),
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text("Export for Tally / CA",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
      ),
      body: Column(children: [
        Container(
          color: Colors.black,
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Export Format",
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFFFFF8E1))),
            const SizedBox(height: 12),
            ...["Tally XML", "CA Audit CSV", "Party Aging Report"]
                .map((f) => RadioListTile<String>(
                      title: Text(f,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(_formatDesc(f),
                          style: const TextStyle(fontSize: 12)),
                      value: f,
                      groupValue: _selectedFormat,
                      activeColor: const Color(0xFFFFF8E1),
                      onChanged: (v) => setState(() => _selectedFormat = v!),
                    )),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF8E1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _generate,
                  icon: const Icon(Icons.build, color: Colors.black),
                  label: Text("Generate $_selectedFormat",
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
              if (_generatedData != null) ...[
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 16)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _generatedData!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("✅ Copied to clipboard"),
                        backgroundColor: Colors.black,
                        behavior: SnackBarBehavior.floating));
                  },
                  icon: const Icon(Icons.copy, color: Colors.black),
                  label:
                      const Text("Copy", style: TextStyle(color: Colors.black)),
                ),
              ],
            ]),
          ]),
        ),
        if (_generatedData != null)
          Expanded(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12)),
              child: SelectableText(_generatedData!,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF212121),
                      height: 1.5)),
            ),
          )),
      ]),
    );
  }

  String _formatDesc(String format) {
    switch (format) {
      case "Tally XML":
        return "Import directly into Tally ERP 9 / TallyPrime";
      case "CA Audit CSV":
        return "Full ledger CSV with GST, TDS, deductions for CA";
      case "Party Aging Report":
        return "Outstanding balances by party for collections";
      default:
        return "";
    }
  }
}

// ==========================================
// BANK STATEMENT IMPORT SCREEN
// ==========================================
class BankImportScreen extends StatefulWidget {
  final List<TripLedger> ledgers;
  final Function(String ledgerId, double amount) onMatch;
  const BankImportScreen(
      {super.key, required this.ledgers, required this.onMatch});
  @override
  State<BankImportScreen> createState() => _BankImportScreenState();
}

class _BankImportScreenState extends State<BankImportScreen> {
  List<BankEntry> _entries = [];
  bool _hasParsed = false;
  final TextEditingController _pasteCtrl = TextEditingController();

  void _parseCSV(String raw) {
    final lines = raw.trim().split('\n');
    final entries = <BankEntry>[];
    for (int i = 1; i < lines.length; i++) {
      final cols = lines[i].split(',');
      if (cols.length < 4) continue;
      try {
        final entry = BankEntry(
          date: cols[0].trim().replaceAll('"', ''),
          narration: cols.length > 1 ? cols[1].trim().replaceAll('"', '') : '',
          refNo: cols.length > 2 ? cols[2].trim().replaceAll('"', '') : '',
          debit: double.tryParse(cols.length > 3
                  ? cols[3].trim().replaceAll('"', '').replaceAll(',', '')
                  : '0') ??
              0,
          credit: double.tryParse(cols.length > 4
                  ? cols[4].trim().replaceAll('"', '').replaceAll(',', '')
                  : '0') ??
              0,
        );
        if (entry.credit > 0 || entry.debit > 0) entries.add(entry);
      } catch (_) {}
    }

    // Auto-match by party name
    for (final e in entries) {
      for (final l in widget.ledgers) {
        final narr = e.narration.toLowerCase();
        final party = l.partyName.toLowerCase();
        if (narr.contains(party) ||
            party.split(' ').any((w) => w.length > 3 && narr.contains(w))) {
          e.isMatched = true;
          e.matchedLedgerId = l.id;
          break;
        }
      }
    }

    setState(() {
      _entries = entries;
      _hasParsed = true;
    });
  }

  void _applySingleMatch(BankEntry entry) {
    if (entry.matchedLedgerId == null) return;
    widget.onMatch(entry.matchedLedgerId!, entry.credit);
    setState(() => entry.isMatched = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        content:
            Text("✅ ₹${entry.credit.toStringAsFixed(0)} matched to ledger")));
  }

  void _applyAllMatched() {
    int count = 0;
    for (final e in _entries) {
      if (e.isMatched && e.matchedLedgerId != null && e.credit > 0) {
        widget.onMatch(e.matchedLedgerId!, e.credit);
        count++;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        content: Text("✅ $count entries applied to ledgers")));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final matched = _entries.where((e) => e.isMatched).length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8E1),
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text("Bank Statement Import",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
        actions: [
          if (matched > 0)
            TextButton(
              onPressed: _applyAllMatched,
              child: Text("Apply $matched",
                  style: const TextStyle(
                      color: Color(0xFF212121), fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(children: [
        Container(
          color: Colors.black,
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Paste CSV Data",
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFFFFF8E1))),
            const SizedBox(height: 4),
            const Text(
                "Paste your bank statement CSV (Date, Narration, Ref No, Debit, Credit)",
                style: TextStyle(color: Colors.black, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _pasteCtrl,
              maxLines: 5,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                  hintText:
                      "Date,Narration,Ref No,Debit,Credit\n22/04/2026,NEFT FROM RELIANCE INDUSTRIES,REF123456,,185000",
                  hintStyle: TextStyle(fontSize: 10, color: Colors.black[400]),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.black[50]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF8E1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => _parseCSV(_pasteCtrl.text),
                  icon: const Icon(Icons.auto_fix_high, color: Colors.black),
                  label: const Text("Parse & Auto-Match",
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ]),
        ),
        if (_hasParsed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${_entries.length} entries parsed",
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: Colors.black)),
                  Text("$matched auto-matched",
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: matched > 0 ? Colors.black : Colors.black)),
                ]),
          ),
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      const Icon(Icons.file_upload_outlined,
                          size: 60, color: Colors.black),
                      const SizedBox(height: 12),
                      const Text("Paste CSV and tap Parse",
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      const SizedBox(height: 8),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.black[50],
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(
                            "Expected CSV format:\nDate, Narration, Ref No, Debit, Credit\n\nThe system auto-matches credit entries to party names in your ledger.",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center),
                      ),
                    ]))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _entries.length,
                  itemBuilder: (ctx, i) {
                    final e = _entries[i];
                    final matchedLedger = e.matchedLedgerId != null
                        ? widget.ledgers.firstWhere(
                            (l) => l.id == e.matchedLedgerId,
                            orElse: () => widget.ledgers.first)
                        : null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: e.isMatched
                                  ? const Color(0xFFEEEEEE)
                                  : const Color(0xFFEEEEEE))),
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
                                            overflow: TextOverflow.ellipsis),
                                        Text(
                                            "${e.date}${e.refNo.isNotEmpty ? ' • ${e.refNo}' : ''}",
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black)),
                                      ])),
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (e.credit > 0)
                                          Text(
                                              "+₹${e.credit.toStringAsFixed(0)}",
                                              style: const TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14)),
                                        if (e.debit > 0)
                                          Text(
                                              "-₹${e.debit.toStringAsFixed(0)}",
                                              style: const TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13)),
                                      ]),
                                ]),
                            if (matchedLedger != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.black[50],
                                    borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(children: [
                                        const Icon(Icons.check_circle,
                                            size: 14, color: Colors.black),
                                        const SizedBox(width: 6),
                                        Text(
                                            "Matched: ${matchedLedger.partyName} — ₹${matchedLedger.partyPending.toStringAsFixed(0)} pending",
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black,
                                                fontWeight: FontWeight.w600)),
                                      ]),
                                      if (e.credit > 0)
                                        TextButton(
                                            onPressed: () =>
                                                _applySingleMatch(e),
                                            style: TextButton.styleFrom(
                                                foregroundColor: Colors.black,
                                                padding: EdgeInsets.zero,
                                                minimumSize:
                                                    const Size(60, 28)),
                                            child: const Text("Apply",
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12))),
                                    ]),
                              ),
                            ],
                          ]),
                    );
                  }),
        ),
      ]),
    );
  }
}

// ==========================================
// ADVANCED ADMIN SCREEN (Hidden/Dev only)
// ==========================================
class AdvancedAdminScreen extends StatefulWidget {
  final List<TripLedger> ledgers;
  final List<Asset> fleet;
  final List<KredXApplication> kredxApps;
  final List<Driver> drivers;
  final UserProfile userProfile;
  final SubscriptionInfo subscription;
  final VoidCallback onFactoryReset;
  final VoidCallback onUpdate;

  const AdvancedAdminScreen({
    super.key,
    required this.ledgers,
    required this.fleet,
    required this.kredxApps,
    required this.drivers,
    required this.userProfile,
    required this.subscription,
    required this.onFactoryReset,
    required this.onUpdate,
  });

  @override
  State<AdvancedAdminScreen> createState() => _AdvancedAdminScreenState();
}

class _AdvancedAdminScreenState extends State<AdvancedAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalRevenue =
        widget.ledgers.fold(0.0, (s, l) => s + l.freightBilled);
    final totalProfit = widget.ledgers.fold(0.0, (s, l) => s + l.tripProfit);
    final totalPending = widget.ledgers
        .fold(0.0, (s, l) => s + (l.partyPending > 0 ? l.partyPending : 0));
    final overdueCount = widget.ledgers
        .where((l) => l.isPaymentOverdue && l.partyPending > 0)
        .length;
    final activeKredX = widget.kredxApps
        .where((a) =>
            a.status == KredXStatus.submitted ||
            a.status == KredXStatus.underReview)
        .length;
    final docsExpiringSoon = widget.fleet
        .expand((a) => a.docs)
        .where((d) => d.isUploaded && d.expiryDate != "Valid")
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: Colors.black[900],
        iconTheme: const IconThemeData(color: Colors.black),
        title: Row(children: [
          const Icon(Icons.admin_panel_settings, color: Colors.black, size: 20),
          const SizedBox(width: 8),
          const Text("Admin Control Panel",
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
        ]),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF212121),
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          tabs: const [
            Tab(icon: Icon(Icons.analytics, size: 16), text: "Analytics"),
            Tab(icon: Icon(Icons.account_balance, size: 16), text: "Finance"),
            Tab(icon: Icon(Icons.storage, size: 16), text: "Data"),
            Tab(icon: Icon(Icons.settings, size: 16), text: "System"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ---- TAB 1: ANALYTICS ----
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle("Business Overview"),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.4,
                children: [
                  _adminKPI("Total GMV", "₹${_fmt(totalRevenue)}",
                      Icons.account_balance_wallet, Colors.black),
                  _adminKPI("Net Profit", "₹${_fmt(totalProfit)}",
                      Icons.trending_up, Colors.black),
                  _adminKPI("Pending", "₹${_fmt(totalPending)}",
                      Icons.hourglass_top, Colors.black),
                  _adminKPI("Total Trips", "${widget.ledgers.length}",
                      Icons.local_shipping, Colors.black),
                  _adminKPI("Fleet Size", "${widget.fleet.length}",
                      Icons.directions_car, Colors.black),
                  _adminKPI("Drivers", "${widget.drivers.length}", Icons.group,
                      Colors.black),
                  _adminKPI("Overdue Trips", "$overdueCount", Icons.warning,
                      Colors.black),
                  _adminKPI(
                      "Profit Margin",
                      totalRevenue > 0
                          ? "${(totalProfit / totalRevenue * 100).toStringAsFixed(1)}%"
                          : "0%",
                      Icons.pie_chart,
                      Colors.black),
                ],
              ),
              const SizedBox(height: 20),
              _sectionTitle("Top Parties by Revenue"),
              const SizedBox(height: 10),
              ..._topParties().map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key,
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          Text("₹${_fmt(e.value)}",
                              style: const TextStyle(
                                  color: Color(0xFF212121),
                                  fontWeight: FontWeight.w900)),
                        ]),
                  )),
              const SizedBox(height: 20),
              _sectionTitle("Vehicle Performance"),
              const SizedBox(height: 10),
              ..._vehiclePerf().take(5).map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key,
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700)),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text("₹${_fmt(e.value)}",
                                    style: const TextStyle(
                                        color: Color(0xFF212121),
                                        fontWeight: FontWeight.w900)),
                                const Text("revenue",
                                    style: TextStyle(
                                        color: Colors.black38, fontSize: 10)),
                              ]),
                        ]),
                  )),
            ],
          ),

          // ---- TAB 2: FINANCE ----
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle("KredX Applications ($activeKredX pending)"),
              const SizedBox(height: 10),
              ...widget.kredxApps
                  .where((a) =>
                      a.status == KredXStatus.submitted ||
                      a.status == KredXStatus.underReview)
                  .map((app) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.black.withValues(alpha: 0.3))),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(app.partyName,
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: app.statusColor
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: app.statusColor
                                                  .withValues(alpha: 0.4))),
                                      child: Text(app.statusLabel,
                                          style: TextStyle(
                                              color: app.statusColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ]),
                              const SizedBox(height: 8),
                              Text(
                                  "Requested: ₹${_fmt(app.requestedAmount)} | Applied: ${app.appliedDate}",
                                  style: const TextStyle(
                                      color: Color(0x99000000), fontSize: 12)),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black[800],
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8))),
                                    onPressed: () {
                                      app.status = KredXStatus.rejected;
                                      widget.onUpdate();
                                      setState(() {});
                                    },
                                    child: const Text("Reject",
                                        style: TextStyle(
                                            color: Colors.black, fontSize: 12)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8))),
                                    onPressed: () {
                                      app.status = KredXStatus.approved;
                                      app.approvedAmount =
                                          app.requestedAmount * 0.85;
                                      widget.onUpdate();
                                      setState(() {});
                                    },
                                    child: const Text("Approve 85%",
                                        style: TextStyle(
                                            color: Colors.black, fontSize: 12)),
                                  ),
                                ),
                              ]),
                            ]),
                      )),
              if (widget.kredxApps.isEmpty ||
                  !widget.kredxApps.any((a) =>
                      a.status == KredXStatus.submitted ||
                      a.status == KredXStatus.underReview))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                      child: Text("No pending applications",
                          style: TextStyle(color: Colors.black38))),
                ),
              const SizedBox(height: 20),
              _sectionTitle("Overdue Collections"),
              const SizedBox(height: 10),
              ...widget.ledgers
                  .where((l) => l.isPaymentOverdue && l.partyPending > 0)
                  .map((l) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.black.withValues(alpha: 0.3))),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l.partyName,
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w700)),
                                    Text(l.vehicleNo,
                                        style: const TextStyle(
                                            color: Colors.black38,
                                            fontSize: 11)),
                                  ]),
                              Text("₹${_fmt(l.partyPending)}",
                                  style: const TextStyle(
                                      color: Color(0xFF212121),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16)),
                            ]),
                      )),
            ],
          ),

          // ---- TAB 3: DATA MANAGEMENT ----
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle("Export & Backup"),
              const SizedBox(height: 10),
              _adminAction(
                Icons.file_download,
                "Export Master Ledger (CSV)",
                "All trips with financial data",
                Colors.black,
                () {
                  String csv =
                      "Trip ID,Date,Party,Vehicle,Route,Material,E-Way,Freight,Received,Pending,Profit\n";
                  for (var l in widget.ledgers) {
                    csv +=
                        "${l.id},${l.date},\"${l.partyName}\",${l.vehicleNo},\"${l.route}\",\"${l.materialName}\",${l.eWayBillNo},${l.freightBilled},${l.paymentReceived},${l.partyPending},${l.tripProfit}\n";
                  }
                  Clipboard.setData(ClipboardData(text: csv));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("✅ CSV copied to clipboard"),
                      backgroundColor: Colors.black,
                      behavior: SnackBarBehavior.floating));
                },
              ),
              const SizedBox(height: 10),
              _adminAction(
                Icons.verified_user,
                "Export Fleet Compliance Report",
                "All vehicle documents and expiry dates",
                Colors.black,
                () {
                  String csv = "Vehicle,Type,Doc Name,Status,Expiry\n";
                  for (var a in widget.fleet) {
                    for (var d in a.docs) {
                      csv +=
                          "${a.number},${a.type},${d.name},${d.isUploaded ? 'Valid' : 'Missing'},${d.expiryDate}\n";
                    }
                  }
                  Clipboard.setData(ClipboardData(text: csv));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("✅ Fleet compliance CSV copied"),
                      backgroundColor: Colors.black,
                      behavior: SnackBarBehavior.floating));
                },
              ),
              const SizedBox(height: 10),
              _adminAction(
                Icons.people,
                "Export Driver Ledger (CSV)",
                "All driver transactions and balances",
                Colors.black,
                () {
                  String csv =
                      "Driver,Phone,Balance,Tx Date,Type,Amount,Note\n";
                  for (var d in widget.drivers) {
                    for (var t in d.transactions) {
                      csv +=
                          "\"${d.name}\",${d.phone},${d.balance},${t.date},${t.type.name},${t.amount},\"${t.note}\"\n";
                    }
                  }
                  Clipboard.setData(ClipboardData(text: csv));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("✅ Driver ledger CSV copied"),
                      backgroundColor: Colors.black,
                      behavior: SnackBarBehavior.floating));
                },
              ),
              const SizedBox(height: 24),
              _sectionTitle("Dangerous Operations"),
              const SizedBox(height: 10),
              _adminAction(
                Icons.delete_forever,
                "Factory Reset — Wipe All Data",
                "⚠️ Permanent. Cannot be undone.",
                Colors.black,
                () => showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: const Color(0xFFFFF8E1),
                    title: const Text("⚠️ Factory Reset",
                        style: TextStyle(
                            color: Color(0xFF212121),
                            fontWeight: FontWeight.bold)),
                    content: const Text(
                        "This will erase ALL trips, drivers, fleet, and settings. This is irreversible.",
                        style: TextStyle(color: Color(0xB3000000))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text("Cancel",
                              style: TextStyle(color: Color(0x99000000)))),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black),
                          onPressed: () {
                            Navigator.pop(c);
                            Navigator.pop(context);
                            widget.onFactoryReset();
                          },
                          child: const Text("WIPE DATA",
                              style: TextStyle(color: Colors.black))),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ---- TAB 4: SYSTEM ----
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle("App Configuration"),
              const SizedBox(height: 10),
              _infoTile("App Version", AppConfig.appVersion),
              _infoTile("Company", widget.userProfile.companyName),
              _infoTile("GSTIN", widget.userProfile.gstin),
              _infoTile("Subscription", widget.subscription.tierName),
              _infoTile("Trips This Month",
                  "${widget.subscription.tripsUsedThisMonth}"),
              _infoTile(
                  "Google Maps API",
                  AppConfig.googleMapsApiKey.isEmpty
                      ? "Not configured"
                      : "Configured ✓"),
              _infoTile("Total Ledger Entries", "${widget.ledgers.length}"),
              _infoTile("Fleet Size", "${widget.fleet.length}"),
              _infoTile("Drivers Registered", "${widget.drivers.length}"),
              _infoTile("Doc Expiry Tracked", "$docsExpiringSoon documents"),
              const SizedBox(height: 20),
              _sectionTitle("Subscription Control"),
              const SizedBox(height: 10),
              ...SubscriptionTier.values.map((tier) {
                final isCurrent = widget.subscription.tier == tier;
                final names = ["FREE", "PRO", "BUSINESS"];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    tileColor: isCurrent
                        ? const Color(0xFF212121).withValues(alpha: 0.15)
                        : const Color(0xFFFFF8E1),
                    title: Text(names[tier.index],
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                    trailing: isCurrent
                        ? const Text("ACTIVE",
                            style: TextStyle(
                                color: Color(0xFF212121),
                                fontWeight: FontWeight.w900,
                                fontSize: 11))
                        : TextButton(
                            onPressed: () {
                              widget.subscription.tier = tier;
                              widget.onUpdate();
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                      "Subscription set to ${names[tier.index]}"),
                                  backgroundColor: Colors.black,
                                  behavior: SnackBarBehavior.floating));
                            },
                            child: Text("Set ${names[tier.index]}",
                                style:
                                    TextStyle(color: const Color(0xFF212121)))),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, double>> _topParties() {
    final Map<String, double> map = {};
    for (final l in widget.ledgers) {
      map[l.partyName] = (map[l.partyName] ?? 0) + l.freightBilled;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  List<MapEntry<String, double>> _vehiclePerf() {
    final Map<String, double> map = {};
    for (final l in widget.ledgers) {
      map[l.vehicleNo] = (map[l.vehicleNo] ?? 0) + l.freightBilled;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  String _fmt(double v) => v >= 100000
      ? "${(v / 100000).toStringAsFixed(1)}L"
      : v >= 1000
          ? "${(v / 1000).toStringAsFixed(1)}K"
          : v.toStringAsFixed(0);

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(
          color: Color(0xB3000000),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2));

  Widget _adminKPI(String label, String value, IconData icon, Color c) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(
                  color: Colors.black38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _adminAction(IconData icon, String title, String subtitle, Color c,
          VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withValues(alpha: 0.2))),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: c, size: 20)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.black38, fontSize: 11)),
                ])),
            Icon(Icons.chevron_right, color: c, size: 20),
          ]),
        ),
      );

  Widget _infoTile(String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(10)),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(color: Color(0x99000000), fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ]),
      );
}

extension on Color {
  Color? operator [](int other) {
    return null;
  }
}

// ==========================================
// KREDX SCREEN
// ==========================================
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
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(c2).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 28),
          child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.black[50],
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.account_balance,
                        color: Colors.black[700], size: 28)),
                const SizedBox(width: 12),
                const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("KredX Invoice Finance",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      Text("Get paid early. Pay later.",
                          style: TextStyle(color: Colors.black, fontSize: 12)),
                    ]),
              ]),
              const SizedBox(height: 24),
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.black[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black[200]!)),
                  child: Column(children: [
                    _kRow("Party", ledger.partyName),
                    _kRow("Invoice Amount",
                        "₹${ledger.partyPending.toStringAsFixed(0)}"),
                    _kRow("You Get (85%)", "₹${max.toStringAsFixed(0)}"),
                    _kRow("Interest Rate", "1.5% / month"),
                  ])),
              const SizedBox(height: 20),
              const Text("Request Amount",
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFFFFF8E1))),
              Slider(
                value: req,
                min: 5000,
                max: max > 5000 ? max : 5001,
                activeColor: Colors.black[700],
                label: "₹${req.toStringAsFixed(0)}",
                onChanged: (v) => setSt(() => req = v),
              ),
              Center(
                  child: Text("₹${req.toStringAsFixed(0)}",
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.black[700]))),
              const SizedBox(height: 16),
              Row(
                  children: [30, 60, 90]
                      .map((t) => Expanded(
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: GestureDetector(
                                  onTap: () => setSt(() => tenure = t),
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      decoration: BoxDecoration(
                                          color: tenure == t
                                              ? const Color(0xFFFFF8E1)
                                              : Colors.black[100],
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Center(
                                          child: Text("$t Days",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: tenure == t
                                                      ? Colors.black
                                                      : Colors.black))))))))
                      .toList()),
              const SizedBox(height: 16),
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.black[50],
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(children: [
                    _kRow("Est. Interest",
                        "₹${(req * 0.015 * (tenure / 30)).toStringAsFixed(0)}"),
                    _kRow("Net Disbursed",
                        "₹${(req - req * 0.015 * (tenure / 30)).toStringAsFixed(0)}",
                        bold: true),
                  ])),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black[700],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          backgroundColor: Colors.black,
                          behavior: SnackBarBehavior.floating,
                          content: Text("✅ KredX application submitted!")));
                    },
                    child: const Text("Submit to KredX",
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  )),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _kRow(String l, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l,
            style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                color: Colors.black54,
                fontSize: 13)),
        Text(v,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: bold ? 15 : 13,
                color: const Color(0xFFFFF8E1))),
      ]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8E1),
        iconTheme: const IconThemeData(color: Colors.black),
        title: Row(children: [
          Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: Colors.black[700],
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.account_balance,
                  color: Colors.black, size: 18)),
          const SizedBox(width: 10),
          const Text("KredX Invoice Finance",
              style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 16)),
        ]),
        bottom: TabBar(
            controller: _tabs,
            indicatorColor: Colors.black,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black54,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: "Eligible Invoices"),
              Tab(text: "My Applications")
            ]),
      ),
      body: TabBarView(controller: _tabs, children: [
        eligible.isEmpty
            ? const Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 60, color: Colors.black),
                    SizedBox(height: 12),
                    Text("No eligible invoices",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black)),
                    Text("Invoices with ₹5000+ pending qualify",
                        style: TextStyle(color: Colors.black)),
                  ]))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: eligible.length,
                itemBuilder: (c, i) {
                  final l = eligible[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10)
                        ]),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(l.partyName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16)),
                                      Text("${l.vehicleNo} • ${l.date}",
                                          style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 12)),
                                    ]),
                                Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                          "₹${l.partyPending.toStringAsFixed(0)}",
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18,
                                              color: Colors.black)),
                                      const Text("pending",
                                          style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 11)),
                                    ]),
                              ]),
                          const Divider(height: 16),
                          Row(children: [
                            Expanded(
                                child: Column(children: [
                              const Text("Invoice",
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              Text("₹${l.freightBilled.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                            ])),
                            Expanded(
                                child: Column(children: [
                              const Text("You Get (85%)",
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  "₹${(l.partyPending * 0.85).toStringAsFixed(0)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black)),
                            ])),
                          ]),
                          const SizedBox(height: 12),
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black[700],
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10))),
                                onPressed: () => _apply(l),
                                icon: const Icon(Icons.account_balance,
                                    color: Colors.black, size: 16),
                                label: const Text("Apply for Advance",
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold)),
                              )),
                        ]),
                  );
                }),
        widget.kredxApps.isEmpty
            ? const Center(
                child: Text("No applications yet",
                    style: TextStyle(color: Colors.black)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: widget.kredxApps.length,
                itemBuilder: (c, i) {
                  final app = widget.kredxApps[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10)
                        ]),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                              color: Colors.black,
                                              fontSize: 12)),
                                    ]),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: app.statusColor
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: app.statusColor
                                                .withValues(alpha: 0.4))),
                                    child: Text(app.statusLabel,
                                        style: TextStyle(
                                            color: app.statusColor,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12))),
                              ]),
                          const Divider(height: 16),
                          Row(children: [
                            Expanded(
                                child: Column(children: [
                              const Text("Requested",
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              Text("₹${app.requestedAmount.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black))
                            ])),
                            Expanded(
                                child: Column(children: [
                              const Text("Approved",
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  app.approvedAmount > 0
                                      ? "₹${app.approvedAmount.toStringAsFixed(0)}"
                                      : "Pending",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black))
                            ])),
                            Expanded(
                                child: Column(children: [
                              const Text("Tenure",
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              Text("${app.tenureDays}d",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black))
                            ])),
                          ]),
                        ]),
                  );
                }),
      ]),
    );
  }
}

// ==========================================
// LIVE TRACKING SCREEN
// ==========================================
class LiveTrackingScreen extends StatefulWidget {
  final String route, vehicleNo;
  const LiveTrackingScreen(
      {super.key, required this.route, required this.vehicleNo});
  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.12;
  Timer? _timer;
  late AnimationController _pulse;
  int _etaMins = 260;
  String _status = "On Route";
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _log.insert(
        0, "${_t()} — Dispatched from ${widget.route.split('→').first.trim()}");
    _log.insert(0, "${_t()} — E-Way Bill verified & GPS active");
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() {
        if (_progress < 0.94) {
          _progress += 0.012 + math.Random().nextDouble() * 0.012;
          _etaMins = (260 * (1 - _progress)).toInt();
          if (_progress > 0.25 && _progress < 0.28) {
            _status = "Toll Plaza";
            _log.insert(0, "${_t()} — FASTag scan at toll");
          }
          if (_progress > 0.48 && _progress < 0.52) {
            _status = "Driver Break";
            _log.insert(0, "${_t()} — Rest stop (15 min)");
          }
          if (_progress > 0.78 && _progress < 0.82) {
            _status = "Approaching Dest.";
            _log.insert(0, "${_t()} — ~$_etaMins mins to destination");
          }
        } else {
          _status = "Arrived ✓";
          if (_log.first != "${_t()} — Arrived at destination") {
            _log.insert(0, "${_t()} — Arrived at destination");
          }
        }
      });
    });
  }

  String _t() {
    final t = DateTime.now();
    return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
  }

  String _eta(int m) {
    if (m <= 0) return "Arrived";
    int h = m ~/ 60, min = m % 60;
    return h > 0 ? "${h}h ${min}m" : "${min}m";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8E1),
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(widget.vehicleNo,
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.w900)),
        actions: [
          Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.black.withValues(alpha: 0.5))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: Colors.black
                                .withValues(alpha: 0.5 + _pulse.value * 0.5),
                            shape: BoxShape.circle))),
                const SizedBox(width: 6),
                const Text("LIVE",
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 12)),
              ])),
        ],
      ),
      body: Column(children: [
        Expanded(
          flex: 3,
          child: Container(
            color: const Color(0xFFFFF8E1),
            child: Stack(children: [
              CustomPaint(painter: _MapGridPainter(), size: Size.infinite),
              Positioned(
                  left: 40,
                  right: 40,
                  top: 0,
                  bottom: 0,
                  child: Center(
                      child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                              color: const Color(0x3D000000),
                              borderRadius: BorderRadius.circular(2))))),
              Positioned(
                  left: 40,
                  right: 40,
                  top: 0,
                  bottom: 0,
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                          widthFactor: _progress,
                          child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF212121),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                        color: const Color(0xFF212121)
                                            .withValues(alpha: 0.5),
                                        blurRadius: 8)
                                  ]))))),
              const Positioned(
                  left: 36,
                  top: 0,
                  bottom: 0,
                  child: Center(
                      child:
                          Icon(Icons.circle, color: Colors.black, size: 14))),
              const Positioned(
                  right: 36,
                  top: 0,
                  bottom: 0,
                  child: Center(
                      child: Icon(Icons.location_on,
                          color: Colors.black, size: 22))),
              Positioned(
                left: 40 +
                    (_progress * (MediaQuery.of(context).size.width - 80)) -
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
                                color: const Color(0xFF212121),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: const Color(0xFF212121).withValues(
                                          alpha: 0.4 + _pulse.value * 0.4),
                                      blurRadius: 12 + _pulse.value * 8,
                                      spreadRadius: 2)
                                ]),
                            child: const Icon(Icons.local_shipping,
                                color: Colors.black, size: 14)))),
              ),
              Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black12)),
                      child: Text(widget.route,
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 11),
                          textAlign: TextAlign.center))),
              Positioned(
                  bottom: 14,
                  left: 14,
                  right: 14,
                  child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black12)),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(children: [
                              const Text("ETA",
                                  style: TextStyle(
                                      color: Color(0x99000000),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                              Text(_eta(_etaMins),
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18))
                            ]),
                            Container(
                                width: 1,
                                height: 28,
                                color: const Color(0x3D000000)),
                            Column(children: [
                              const Text("Progress",
                                  style: TextStyle(
                                      color: Color(0x99000000),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                              Text("${(_progress * 100).toStringAsFixed(0)}%",
                                  style: const TextStyle(
                                      color: Color(0xFF212121),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18))
                            ]),
                            Container(
                                width: 1,
                                height: 28,
                                color: const Color(0x3D000000)),
                            Column(children: [
                              const Text("Status",
                                  style: TextStyle(
                                      color: Color(0x99000000),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  _status.length > 14
                                      ? "${_status.substring(0, 13)}…"
                                      : _status,
                                  style: const TextStyle(
                                      color: Color(0xFF212121),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11))
                            ]),
                          ]))),
            ]),
          ),
        ),
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.black,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Journey Progress",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: Color(0xFFFFF8E1))),
                              Text("${(_progress * 100).toStringAsFixed(1)}%",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF212121))),
                            ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                                value: _progress,
                                backgroundColor: Colors.black[200],
                                color: const Color(0xFF212121),
                                minHeight: 10)),
                      ])),
              Expanded(
                  child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      itemCount: _log.length,
                      itemBuilder: (c, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(children: [
                            const Icon(Icons.fiber_manual_record,
                                size: 8, color: Color(0xFF212121)),
                            const SizedBox(width: 8),
                            Text(_log[i],
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500)),
                          ])))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final rp = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
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

// ==========================================
// DRIVER LEDGER SCREEN
// ==========================================
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
                      color: Colors.black,
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
                            color: Color(0xFFFFF8E1))),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<DriverTxType>(
                        initialValue: type,
                        decoration: InputDecoration(
                            labelText: "Transaction Type",
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12))),
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
                        controller: amtCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: "Amount (₹)",
                            prefixIcon: const Icon(Icons.currency_rupee),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: noteCtrl,
                        decoration: InputDecoration(
                            labelText: "Notes",
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)))),
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
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)))),
                    const SizedBox(height: 20),
                  ]),
                )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor: const Color(0xFFFFF8E1),
          iconTheme: const IconThemeData(color: Colors.black),
          title: Text(widget.driver.name,
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w900))),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: const BoxDecoration(
              color: Color(0xFFFFF8E1),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32))),
          child: Column(children: [
            const Text("Outstanding Balance",
                style: TextStyle(
                    color: Color(0x99000000),
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text("₹${widget.driver.balance.toStringAsFixed(0)}",
                style: TextStyle(
                    color: widget.driver.balance >= 0
                        ? const Color(0xFF212121)
                        : const Color(0xFF212121),
                    fontSize: 44,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
                widget.driver.balance >= 0
                    ? "Owed to driver"
                    : "Driver owes company",
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
            if (widget.driver.monthlySalary > 0) ...[
              const SizedBox(height: 8),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(
                      "Monthly Salary: ₹${widget.driver.monthlySalary.toStringAsFixed(0)}",
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 12))),
            ],
          ]),
        ),
        Expanded(
            child: widget.driver.transactions.isEmpty
                ? const Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Icon(Icons.receipt_outlined,
                            size: 50, color: Colors.black),
                        SizedBox(height: 10),
                        Text("No transactions",
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
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
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 8)
                              ]),
                          child: ListTile(
                              contentPadding: const EdgeInsets.all(14),
                              leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                      color: pos
                                          ? Colors.black[50]
                                          : Colors.black[50],
                                      shape: BoxShape.circle),
                                  child: Icon(pos ? Icons.arrow_downward : Icons.arrow_upward,
                                      color: pos ? Colors.black : Colors.black,
                                      size: 18)),
                              title: Text(tx.type.name.toUpperCase(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13)),
                              subtitle: Text("${tx.date}${tx.note.isNotEmpty ? ' • ${tx.note}' : ''}",
                                  style: const TextStyle(
                                      color: Colors.black, fontSize: 11)),
                              trailing: Text(
                                  "${pos ? '+' : ''}₹${tx.amount.abs().toStringAsFixed(0)}",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: pos ? Colors.black : Colors.black))));
                    })),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFFFFF8E1),
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text("Add Entry",
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          onPressed: _addTx),
    );
  }
}

// ==========================================
// PIE CHART PAINTER
// ==========================================
class NativePieChartPainter extends CustomPainter {
  final double revenue, expense;
  NativePieChartPainter({required this.revenue, required this.expense});

  @override
  void paint(Canvas canvas, Size size) {
    double total = revenue + expense;
    if (total == 0) return;
    double rAngle = (revenue / total) * 2 * math.pi;
    Rect rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width / 2);
    canvas.drawArc(
        rect,
        -math.pi / 2,
        rAngle,
        true,
        Paint()
          ..color = const Color(0xFF212121)
          ..style = PaintingStyle.fill);
    canvas.drawArc(
        rect,
        -math.pi / 2 + rAngle,
        2 * math.pi - rAngle,
        true,
        Paint()
          ..color = const Color(0xFF212121).withValues(alpha: 0.8)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 3,
        Paint()..color = const Color(0xFFFFF8E1));
    final tp = TextPainter(
        text: TextSpan(
            text: "${(revenue / total * 100).toStringAsFixed(0)}%",
            style: const TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas,
        Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => true;
}
