import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'main.dart'; // Grabs your API Key

// ---------------------------------------------------------
// CAMERA HELPER (Replaces the broken FilePicker)
// ---------------------------------------------------------
class ImgHelper {
  static Future<XFile?> pick(BuildContext c) async {
    final s = await showModalBottomSheet<ImageSource>(
      context: c,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera (Scan)'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    return s != null
        ? await ImagePicker().pickImage(source: s, imageQuality: 50)
        : null;
  }
}

// ---------------------------------------------------------
// 1. FLEET MANAGER & ASSET VAULT
// ---------------------------------------------------------
class Fleet extends StatelessWidget {
  const Fleet({super.key});

  bool _isExp(dynamic ts) {
    if (ts == null) return true;
    return (ts as Timestamp).toDate().isBefore(
          DateTime.now().add(const Duration(days: 15)),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fleet & Vault'),
        backgroundColor: const Color(0xFFFFF8E1),
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('trucks').snapshots(),
        builder: (c, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            itemCount: s.data!.docs.length,
            itemBuilder: (c, i) {
              final doc = s.data!.docs[i];
              final d = doc.data() as Map<String, dynamic>;

              // Smart Expiry Check (RC, Ins, PUC, Calib, Form XI)
              bool alert = _isExp(d['rcExp']) ||
                  _isExp(d['insExp']) ||
                  _isExp(d['pucExp']) ||
                  _isExp(d['calibExp']) ||
                  _isExp(d['formXiExp']);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: alert ? Colors.black.shade50 : Colors.black,
                child: ExpansionTile(
                  leading: Icon(
                    Icons.local_shipping,
                    color: alert ? Colors.black : const Color(0xFFFFF8E1),
                  ),
                  title: Text(
                    d['truckNo'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    alert
                        ? 'âš ï¸ Action Required (Expiring)'
                        : 'All Documents Valid',
                    style: TextStyle(
                      color: alert ? Colors.black : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Health & Assets',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Divider(),
                          Text(
                            'Tyres (${d['tCount'] ?? '0'}): ${d['tNos'] ?? 'Not Logged'}',
                          ),
                          Text(
                            'Battery: ${d['bNo'] ?? 'Not Logged'} | Warranty: ${d['bWar'] ?? 'N/A'}',
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Document Vault',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Divider(),
                          _vBtn(context, doc.id, 'RC', d['rcExp']),
                          _vBtn(context, doc.id, 'Insurance', d['insExp']),
                          _vBtn(context, doc.id, 'PUC', d['pucExp']),
                          _vBtn(context, doc.id, 'Calibration', d['calibExp']),
                          _vBtn(context, doc.id, 'Form XI', d['formXiExp']),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () => doc.reference.delete(),
                            icon: const Icon(Icons.delete, color: Colors.black),
                            label: const Text(
                              'Delete Vehicle',
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (c) => const AddTruck(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _vBtn(BuildContext c, String id, String label, dynamic exp) {
    bool alert = _isExp(exp);
    String date = exp != null
        ? DateFormat('dd/MM/yy').format((exp as Timestamp).toDate())
        : 'Missing';
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(
        'Exp: $date',
        style: TextStyle(
          color: alert ? Colors.black : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      trailing: const Icon(Icons.camera_alt, color: Color(0xFFFFF8E1)),
      onTap: () async {
        final img = await ImgHelper.pick(c);
        if (img != null) {
          DateTime? dt = await showDatePicker(
            context: c,
            initialDate: DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
          );
          if (dt != null) {
            await FirebaseFirestore.instance
                .collection('trucks')
                .doc(id)
                .update({
              '${label.toLowerCase().replaceAll(' ', '')}Exp':
                  Timestamp.fromDate(dt),
            });
          }
        }
      },
    );
  }
}

extension on Color {
  get shade50 => null;
}

class AddTruck extends StatefulWidget {
  const AddTruck({super.key});
  @override
  State<AddTruck> createState() => _AddTruckState();
}

class _AddTruckState extends State<AddTruck> {
  final _n = TextEditingController();
  final _tc = TextEditingController();
  final _tn = TextEditingController();
  final _bn = TextEditingController();
  final _bw = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Vehicle',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _n,
              decoration: const InputDecoration(
                labelText: 'Truck No (e.g. GJ01...)',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tc,
                    decoration: const InputDecoration(labelText: 'Tyre Count'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _tn,
                    decoration: const InputDecoration(
                      labelText: 'Tyre Serials',
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bn,
                    decoration: const InputDecoration(
                      labelText: 'Battery Serial',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _bw,
                    decoration: const InputDecoration(
                      labelText: 'Battery Warranty (Mos)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('trucks').add({
                    'truckNo': _n.text.toUpperCase(),
                    'tCount': _tc.text,
                    'tNos': _tn.text,
                    'bNo': _bn.text,
                    'bWar': _bw.text,
                  });
                  Navigator.pop(context);
                },
                child: const Text('Save Asset'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. DRIVERS & AI DL SCANNER
// ---------------------------------------------------------
class Drivers extends StatelessWidget {
  const Drivers({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drivers Database'),
        backgroundColor: const Color(0xFFFFF8E1),
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
        builder: (c, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            itemCount: s.data!.docs.length,
            itemBuilder: (c, i) {
              final doc = s.data!.docs[i];
              final d = doc.data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF8E1),
                    child: Icon(Icons.person, color: Colors.black),
                  ),
                  title: Text(
                    d['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'DL: ${d['dl']}\nAdd: ${d['add']}\nHazmat: ${d['haz']}',
                    style: const TextStyle(height: 1.4),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.black),
                    onPressed: () => doc.reference.delete(),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (c) => const AddDriver(),
        ),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

class AddDriver extends StatefulWidget {
  const AddDriver({super.key});
  @override
  State<AddDriver> createState() => _AddDriverState();
}

class _AddDriverState extends State<AddDriver> {
  final _n = TextEditingController();
  final _dl = TextEditingController();
  final _ad = TextEditingController();
  final _hz = TextEditingController();
  bool _scan = false;

  static const String kVisionApiKey =
      ''; // TODO: Add your Google Vision API key

  void _scanDL() async {
    final img = await ImgHelper.pick(context);
    if (img == null) return;
    setState(() => _scan = true);
    try {
      final res = await http.post(
        Uri.parse(
          'https://vision.googleapis.com/v1/images:annotate?key=$kVisionApiKey',
        ),
        body: jsonEncode({
          "requests": [
            {
              "image": {"content": base64Encode(await img.readAsBytes())},
              "features": [
                {"type": "TEXT_DETECTION"},
              ],
            },
          ],
        }),
      );
      String txt = jsonDecode(
        res.body,
      )['responses'][0]['textAnnotations'][0]['description']
          .toString()
          .toUpperCase();

      var dlM = RegExp(
        r'([A-Z]{2}[0-9]{13})',
      ).firstMatch(txt.replaceAll(RegExp(r'\s+|-'), ''));
      if (dlM != null) _dl.text = dlM.group(0)!;
      if (txt.contains('ADDRESS') || txt.contains('ADD')) {
        var pin = RegExp(r'\d{6}').firstMatch(txt);
        _ad.text =
            pin != null ? "PIN Code Found: ${pin.group(0)}" : "Address Found";
      }
      if (txt.contains('HAZARDOUS') || txt.contains('HAZMAT')) {
        _hz.text = "Hazmat Certified";
      } else {
        _hz.text = "Not Certified";
      }
    } finally {
      setState(() => _scan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add Driver',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _scanDL,
                  icon: _scan
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.document_scanner),
                  label: const Text('Smart Scan DL'),
                ),
              ],
            ),
            TextField(
              controller: _n,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _dl,
              decoration: const InputDecoration(labelText: 'DL No'),
            ),
            TextField(
              controller: _ad,
              decoration: const InputDecoration(labelText: 'Extracted Address'),
            ),
            TextField(
              controller: _hz,
              decoration: const InputDecoration(labelText: 'Hazmat Status'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('drivers').add({
                    'name': _n.text,
                    'dl': _dl.text,
                    'add': _ad.text,
                    'haz': _hz.text,
                  });
                  Navigator.pop(context);
                },
                child: const Text('Save Driver'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
