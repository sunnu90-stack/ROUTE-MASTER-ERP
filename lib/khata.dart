import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
// ignore: unused_import
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'fleet.dart'; // To use the ImgHelper for LR Scanning

class Khata extends StatefulWidget {
  const Khata({super.key});
  @override
  State<Khata> createState() => _KhataState();
}

class _KhataState extends State<Khata> {
  String _pF = 'All Parties';
  String _tF = 'All Trucks';

  // PDF: Monthly Statement Generator
  void _pdf(List<QueryDocumentSnapshot> docs) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'FreightMaster ERP Statement',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Party: $_pF | Vehicle: $_tF',
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Party', 'Type', 'Desc', 'Amount'],
              data: docs.map((d) {
                final m = d.data() as Map;
                return [
                  DateFormat(
                    'dd/MM/yy',
                  ).format((m['date'] as Timestamp).toDate()),
                  m['p'],
                  m['type'],
                  m['desc'] ?? '',
                  'Rs. ${m['amt']}',
                ];
              }).toList(),
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // PDF: Lorry Receipt (Bilty) Generator
  void _bilty(Map m) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Container(
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'LORRY RECEIPT / BILTY',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Divider(),
              pw.SizedBox(height: 20),
              pw.Text(
                'Consignor / Party: ${m['p']}',
                style: const pw.TextStyle(fontSize: 18),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Vehicle Number: ${m['trk']}',
                style: const pw.TextStyle(fontSize: 18),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Route / Description: ${m['desc']}',
                style: const pw.TextStyle(fontSize: 18),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Total Freight: Rs. ${m['amt']}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khata Ledger'),
        backgroundColor: const Color(0xFFFFF8E1),
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          // FILTER HEADER
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Party Filter',
                    ),
                    initialValue: _pF,
                    items: ['All Parties', 'Reliance', 'Tata', 'Adani']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _pF = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('trucks')
                        .snapshots(),
                    builder: (c, s) {
                      List<String> t = ['All Trucks'];
                      if (s.hasData) {
                        t.addAll(
                          s.data!.docs.map((d) => d['truckNo'].toString()),
                        );
                      }
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Vehicle Filter',
                        ),
                        initialValue: _tF,
                        items: t
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _tF = v!),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('transactions')
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (c, s) {
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = s.data!.docs.where((d) {
                  final m = d.data() as Map;
                  return (_pF == 'All Parties' || m['p'] == _pF) &&
                      (_tF == 'All Trucks' || m['trk'] == _tF);
                }).toList();
                double net = 0;
                for (var d in docs) {
                  final m = d.data() as Map;
                  double a = double.tryParse(m['amt'].toString()) ?? 0;
                  m['type'] == 'Receivable' ? net += a : net -= a;
                }

                return Column(
                  children: [
                    // LEDGER GRAPHICS (Red/Green Net Balance) & PDF EXPORT
                    Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: net >= 0 ? Colors.grey[800]! : Colors.grey[800]!,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                net >= 0
                                    ? 'Party Owes You (Net)'
                                    : 'You Owe Party (Net)',
                                style: const TextStyle(color: Colors.black),
                              ),
                              Text(
                                'â‚¹ ${net.abs()}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _pdf(docs),
                              icon: const Icon(
                                Icons.picture_as_pdf,
                                color: Color(0xFFFFF8E1),
                              ),
                              label: const Text(
                                'Export Monthly Statement',
                                style: TextStyle(color: Colors.black),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (c, i) {
                          final doc = docs[i];
                          final m = doc.data() as Map<String, dynamic>;
                          bool lr = m['lr'] == true;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              title: Text(
                                m['p'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${m['type']} â€¢ Trk: ${m['trk']}\nDesc: ${m['desc']}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'â‚¹${m['amt']}',
                                    style: TextStyle(
                                      color: m['type'] == 'Receivable'
                                          ? Colors.black
                                          : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      lr
                                          ? Icons.check_circle
                                          : Icons.camera_alt,
                                      color: lr ? Colors.black : Colors.black,
                                    ),
                                    onPressed: () async {
                                      final img = await ImgHelper.pick(context);
                                      if (img != null) {
                                        doc.reference.update({'lr': true});
                                      }
                                    },
                                  ),
                                  if (m['type'] == 'Receivable' ||
                                      m['type'] == 'Commission')
                                    IconButton(
                                      icon: const Icon(
                                        Icons.receipt_long,
                                        color: Colors.black,
                                      ),
                                      onPressed: () => _bilty(m),
                                    ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.black,
                                      size: 20,
                                    ),
                                    onPressed: () => doc.reference.delete(),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (c) => const AddEntry(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AddEntry extends StatefulWidget {
  const AddEntry({super.key});
  @override
  State<AddEntry> createState() => _AddEntryState();
}

class _AddEntryState extends State<AddEntry> {
  String _t = 'Receivable';
  final _p = TextEditingController();
  final _d = TextEditingController();
  final _a = TextEditingController();
  final _l = TextEditingController();
  final _r = TextEditingController();
  String? _trk;

  // DIESEL CALCULATOR
  void _calc() {
    double l = double.tryParse(_l.text) ?? 0;
    double r = double.tryParse(_r.text) ?? 0;
    if (l > 0 && r > 0) _a.text = (l * r).toStringAsFixed(0);
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
            const Text(
              'New Ledger Entry',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _t,
              items: [
                'Receivable',
                'Payable',
                'Diesel Expense',
                'FASTag',
                'Repair',
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _t = v!),
            ),
            if (_t == 'Diesel Expense')
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _l,
                      decoration: const InputDecoration(labelText: 'Liters'),
                      onChanged: (v) => _calc(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _r,
                      decoration: const InputDecoration(labelText: 'Rate/Ltr'),
                      onChanged: (v) => _calc(),
                    ),
                  ),
                ],
              ),
            TextField(
              controller: _p,
              decoration: const InputDecoration(labelText: 'Party/Mechanic'),
            ),
            TextField(
              controller: _d,
              decoration: const InputDecoration(labelText: 'Route/Desc'),
            ),
            TextField(
              controller: _a,
              decoration: const InputDecoration(labelText: 'Amount (â‚¹)'),
            ),
            StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('trucks').snapshots(),
              builder: (c, s) {
                if (!s.hasData) return const SizedBox();
                return DropdownButtonFormField<String>(
                  hint: const Text('Select Vehicle'),
                  items: s.data!.docs
                      .map(
                        (d) => DropdownMenuItem(
                          value: d['truckNo'].toString(),
                          child: Text(d['truckNo'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => _trk = v,
                );
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('transactions')
                      .add({
                    'p': _p.text,
                    'desc': _d.text,
                    'amt': _a.text,
                    'type': _t,
                    'trk': _trk ?? 'Market',
                    'date': DateTime.now(),
                    'lr': false,
                  });
                  Navigator.pop(context);
                },
                child: const Text('Save Entry'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
