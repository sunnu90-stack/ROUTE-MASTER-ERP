import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _isPosting = false; // Toggle between Find/Book and Post Load

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Market & Analytics'),
        backgroundColor: const Color(0xFFFFF8E1),
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. DYNAMIC NET PROFIT GRAPHIC
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('transactions')
                  .snapshots(),
              builder: (context, snapshot) {
                double rev = 0;
                double exp = 0;
                if (snapshot.hasData) {
                  for (var d in snapshot.data!.docs) {
                    final m = d.data() as Map<String, dynamic>;
                    double a = double.tryParse(m['amount'].toString()) ?? 0;
                    if (m['type'] == 'Receivable' ||
                        m['type'] == 'Commission') {
                      rev += a;
                    } else {
                      exp += a;
                    }
                  }
                }
                return Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFF8E1), Color(0xFF000000)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Net Profit',
                        style: TextStyle(color: Color(0xB3000000)),
                      ),
                      Text(
                        'â‚¹ ${(rev - exp).toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(color: Color(0x3D000000), height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Rev: â‚¹$rev',
                            style: const TextStyle(
                              color: Color(0x8A000000),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Exp: â‚¹$exp',
                            style: const TextStyle(
                              color: Color(0x8A000000),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            // 2. POST LOAD / BOOK LOAD TOGGLE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Find & Book',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Switch(
                    value: _isPosting,
                    activeThumbColor: const Color(0xFFFFF8E1),
                    onChanged: (v) => setState(() => _isPosting = v),
                  ),
                  const Text(
                    'Post & Commission',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // 3. UI SWITCHER
            _isPosting ? const PostLoadWidget() : const FindLoadWidget(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// POST LOAD & COMMISSION WIDGET
// ---------------------------------------------------------
class PostLoadWidget extends StatefulWidget {
  const PostLoadWidget({super.key});
  @override
  State<PostLoadWidget> createState() => _PostLoadWidgetState();
}

class _PostLoadWidgetState extends State<PostLoadWidget> {
  final _route = TextEditingController();
  final _freight = TextEditingController();
  final _comm = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Post Market Load',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _route,
                decoration: const InputDecoration(
                  labelText: 'Route (e.g. Ahmedabad to Delhi)',
                ),
              ),
              TextField(
                controller: _freight,
                decoration: const InputDecoration(
                  labelText: 'Total Freight (â‚¹)',
                ),
              ),
              TextField(
                controller: _comm,
                decoration: const InputDecoration(
                  labelText: 'Your Commission Cut (â‚¹)',
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('transactions')
                        .add({
                      'partyName': 'Market Commission',
                      'route': _route.text,
                      'amount': _comm.text,
                      'type': 'Commission',
                      'linkedTruck': 'Market',
                      'date': DateTime.now(),
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Load Posted & Commission Logged!'),
                      ),
                    );
                  },
                  child: const Text('Post & Log Commission'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// FIND LOAD & SELF-TANKER CALC WIDGET
// ---------------------------------------------------------
class FindLoadWidget extends StatelessWidget {
  const FindLoadWidget({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ListTile(
          title: Text('Ahmedabad to Delhi'),
          subtitle: Text('Liquid Tanker - 25 Tons'),
          trailing: Text(
            'â‚¹ 52,000',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (c) => const SelfTankerCalc(),
              ),
              icon: const Icon(Icons.calculate),
              label: const Text('Calculate Self-Tanker Booking'),
            ),
          ),
        ),
      ],
    );
  }
}

class SelfTankerCalc extends StatefulWidget {
  const SelfTankerCalc({super.key});
  @override
  State<SelfTankerCalc> createState() => _SelfTankerCalcState();
}

class _SelfTankerCalcState extends State<SelfTankerCalc> {
  final _f = TextEditingController();
  final _d = TextEditingController();
  final _m = TextEditingController(text: '4.0');
  final _r = TextEditingController(text: '90');
  final _t = TextEditingController(text: '0');
  String _c = "0";
  String _n = "0";

  void _calc() {
    double d = double.tryParse(_d.text) ?? 0;
    double m = double.tryParse(_m.text) ?? 1;
    double r = double.tryParse(_r.text) ?? 0;
    double t = double.tryParse(_t.text) ?? 0;
    double f = double.tryParse(_f.text) ?? 0;
    double cost = ((d / m) * r) + t;
    setState(() {
      _c = cost.toStringAsFixed(0);
      _n = (f - cost).toStringAsFixed(0);
    });
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
              'Self-Tanker Cost Calculator',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _f,
              decoration: const InputDecoration(
                labelText: 'Total Freight Revenue (â‚¹)',
              ),
              onChanged: (v) => _calc(),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _d,
                    decoration: const InputDecoration(
                      labelText: 'Distance (km)',
                    ),
                    onChanged: (v) => _calc(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _m,
                    decoration: const InputDecoration(
                      labelText: 'Mileage (km/l)',
                    ),
                    onChanged: (v) => _calc(),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _r,
                    decoration: const InputDecoration(
                      labelText: 'Diesel Rate (â‚¹)',
                    ),
                    onChanged: (v) => _calc(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _t,
                    decoration: const InputDecoration(
                      labelText: 'FASTag/Tolls (â‚¹)',
                    ),
                    onChanged: (v) => _calc(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Est. Diesel + Toll Cost:'),
                  Text(
                    'â‚¹ $_c',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Projected Net Profit:'),
                  Text(
                    'â‚¹ $_n',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
