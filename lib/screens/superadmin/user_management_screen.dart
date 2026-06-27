import 'package:flutter/material.dart';

import '../admin/role_feature_screens.dart';

class SuperadminUserManagementScreen extends StatelessWidget {
  const SuperadminUserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      buildSuperadminFeatureScreen('userManagement');
}
