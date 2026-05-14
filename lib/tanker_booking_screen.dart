import 'package:flutter/material.dart';

class TankerBookingScreen extends StatefulWidget {
  const TankerBookingScreen({super.key});

  @override
  State<TankerBookingScreen> createState() => _TankerBookingScreenState();
}

class _TankerBookingScreenState extends State<TankerBookingScreen> {
  // Client Ledger Controllers
  final TextEditingController _clientFreightCtrl = TextEditingController();
  final TextEditingController _clientAdvanceCtrl = TextEditingController();

  // Market Vehicle Ledger Controllers
  final TextEditingController _vendorHireCtrl = TextEditingController();
  final TextEditingController _vendorAdvanceCtrl = TextEditingController();

  bool _isMarketVehicle = false;

  // Payment Terms
  final List<String> _paymentTerms = [
    'On Unloading',
    'Upon LR Upload',
    'Net 10 Days',
    'Net 15 Days',
    'Net 30 Days'
  ];
  String _clientTerm = 'Upon LR Upload';
  String _vendorTerm = 'On Unloading';

  // Dynamic Balance Calculations
  double get _clientBalance {
    double freight = double.tryParse(_clientFreightCtrl.text) ?? 0;
    double advance = double.tryParse(_clientAdvanceCtrl.text) ?? 0;
    return freight - advance;
  }

  double get _vendorBalance {
    double hire = double.tryParse(_vendorHireCtrl.text) ?? 0;
    double advance = double.tryParse(_vendorAdvanceCtrl.text) ?? 0;
    return hire - advance;
  }

  void _submitBooking() {
    // BACKEND DEV NOTE: Add Firebase/API save logic here
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Booking Saved! Notifications triggered.'),
        backgroundColor: Colors.black,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Tanker Booking')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- CLIENT SECTION ---
            const Text('Client Billing (Receivable)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
                controller: _clientFreightCtrl,
                decoration: const InputDecoration(
                    labelText: 'Total Freight (â‚¹)',
                    border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                onChanged: (val) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _clientAdvanceCtrl,
                decoration: const InputDecoration(
                    labelText: 'Advance Received (â‚¹)',
                    border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                onChanged: (val) => setState(() {})),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
                initialValue: _clientTerm,
                decoration: const InputDecoration(
                    labelText: 'Payment Terms', border: OutlineInputBorder()),
                items: _paymentTerms
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) => setState(() => _clientTerm = val!)),
            const SizedBox(height: 10),
            Text('Client Balance Due: â‚¹$_clientBalance',
                style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                    fontWeight: FontWeight.bold)),

            const Divider(height: 40, thickness: 2),

            // --- MARKET VEHICLE TOGGLE ---
            SwitchListTile(
                title: const Text('Use Market Vehicle?',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                value: _isMarketVehicle,
                onChanged: (val) => setState(() => _isMarketVehicle = val)),

            // --- VENDOR SECTION ---
            if (_isMarketVehicle) ...[
              const SizedBox(height: 10),
              const Text('Market Vehicle Settlement',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(
                  controller: _vendorHireCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Total Hire Cost (â‚¹)',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => setState(() {})),
              const SizedBox(height: 10),
              TextField(
                  controller: _vendorAdvanceCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Advance Paid (â‚¹)',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => setState(() {})),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                  initialValue: _vendorTerm,
                  decoration: const InputDecoration(
                      labelText: 'Payment Terms', border: OutlineInputBorder()),
                  items: _paymentTerms
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) => setState(() => _vendorTerm = val!)),
              const SizedBox(height: 10),
              Text('Vendor Balance Due: â‚¹$_vendorBalance',
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                      fontWeight: FontWeight.bold)),
            ],

            const SizedBox(height: 30),

            // --- SUBMIT ---
            SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                    onPressed: _submitBooking,
                    child: const Text('Confirm Booking',
                        style: TextStyle(fontSize: 16)))),
          ],
        ),
      ),
    );
  }
}
