import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FeeDetailsScreen extends StatefulWidget {
  const FeeDetailsScreen({super.key});

  @override
  State<FeeDetailsScreen> createState() => _FeeDetailsScreenState();
}

class _FeeDetailsScreenState extends State<FeeDetailsScreen> {
  Map<String, dynamic>? studentData;
  bool loading = true;
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    fetchFeeDetails();
  }

  Future<void> fetchFeeDetails() async {
    setState(() {
      loading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final username = prefs.getString('username');

    if (token == null || username == null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Session Expired'),
          content: const Text('Please login again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final url = Uri.parse(
        'https://erp.sirhindpublicschool.com:3000/StudentsApp/admission/$username/fees');

    try {
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });

      if (res.statusCode == 200) {
        final jsonData = json.decode(res.body);
        setState(() {
          studentData = jsonData;
        });
      } else if (res.statusCode == 401) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Unauthorized'),
            content: const Text('Please login again.'),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        showError('Failed to fetch fee details');
      }
    } catch (e) {
      showError('An error occurred: $e');
    } finally {
      setState(() {
        loading = false;
        refreshing = false;
      });
    }
  }

  void showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  double calculateTotalDue() {
    if (studentData == null || studentData!['feeDetails'] == null) return 0.0;
    final isOld = (studentData!['admission_type']?.toString().toLowerCase() ?? '') == 'old';

    return studentData!['feeDetails']
        .where((f) => !(isOld && f['fee_heading_id'].toString() == '1'))
        .fold(0.0, (total, f) => total + double.tryParse(f['finalAmountDue'].toString())!);
  }

  Widget buildFeeCard(Map<String, dynamic> fee) {
    final due = double.tryParse(fee['finalAmountDue'].toString()) ?? 0.0;

    return SizedBox(
      width: double.infinity,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fee['fee_heading'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("Original: ₹${fee['originalFeeDue']}"),
              Text("Concession: ₹${fee['totalConcessionReceived']}"),
              const SizedBox(height: 4),
              Text(
                "Final Due: ₹${fee['finalAmountDue']}",
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              due > 0
                  ? ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text("Payment Not Available"),
                            content: const Text("Online payment has been temporarily disabled."),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("OK"),
                              )
                            ],
                          ),
                        );
                      },
                      child: const Text("Pay Now"),
                    )
                  : const Text("Paid", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading && !refreshing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isOldAdmission =
        (studentData!['admission_type']?.toString().toLowerCase() ?? '') == 'old';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Fee Details"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: fetchFeeDetails,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: studentData == null
              ? const Center(child: Text("No data available."))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(studentData!['name'],
                                style: const TextStyle(fontSize: 20, color: Colors.white)),
                            Text("Admission Type: ${studentData!['admission_type']}",
                                style: const TextStyle(color: Colors.white)),
                            Text("Class ID: ${studentData!['class_id']}",
                                style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xfffff7e6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(left: BorderSide(color: Color(0xffff9f43), width: 6)),
                      ),
                      child: Text(
                        "Total Pending Fee: ₹${calculateTotalDue().toStringAsFixed(2)}",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xffff6f00)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...studentData!['feeDetails']
                        .where((fee) =>
                            !(isOldAdmission && fee['fee_heading_id'].toString() == '1'))
                        .map<Widget>((fee) => buildFeeCard(fee))
                        .toList(),
                  ],
                ),
        ),
      ),
    );
  }
}
