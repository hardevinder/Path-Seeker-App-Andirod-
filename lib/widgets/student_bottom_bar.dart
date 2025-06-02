import 'package:flutter/material.dart';

class StudentBottomBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const StudentBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: Colors.blueAccent,
      unselectedItemColor: Colors.grey,
      currentIndex: selectedIndex,
      onTap: onItemTapped,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long),
          label: 'Fee Details',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.assignment),
          label: 'Assignments',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.schedule),
          label: 'Time Table',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.campaign), // ✅ New icon
          label: 'Circulars',         // ✅ Updated label
        ),
      ],
    );
  }
}
