import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../main.dart';

Widget buildKPISection(ThemeData theme) {
  return Container(
    padding: EdgeInsets.all(5.w),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("CONSOLE FINANCIÈRE",
            style: theme.textTheme.labelLarge
                ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w900)),
        SizedBox(height: 2.h),
        StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('solde').snapshots(),
          builder: (context, snapshot) {
            final solde = snapshot.hasData && snapshot.data!.docs.isNotEmpty
                ? snapshot.data!.docs
                : null;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ...?solde?.map((item) {
                  final result = item.data() as Map<String, dynamic>;
                  return Expanded(
                    child: Padding(
                      padding:  EdgeInsets.symmetric(horizontal: 1.w),
                      child: _buildKPICard(
                        label: result.keys.single,
                        value: result.values.single != ""
                            ? "${result.values.singleOrNull} F"
                            : "...",
                        color: const Color(0xFF0052FF),
                        icon: Icons.account_balance_wallet_rounded,
                      ),
                    ),
                  );
                }).toList(),

                // _buildKPICard(
                //   label: "Solde POS",
                //   value: solde != null ? "${solde.first["soldepost"]} F" : "...",
                //   color: const Color(0xFF0052FF),
                //   icon: Icons.account_balance_wallet_rounded,
                // ),
                // SizedBox(width: 3.w),
                // _buildKPICard(
                //   label: "DSM Balance",
                //   value: solde != null ? "${solde.last["dsm"]} F" : "...",
                //   color: const Color(0xFF6A1B9A),
                //   icon: Icons.savings_rounded,
                // ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

Widget _buildKPICard(
    {required String label,
    required String value,
    required Color color,
    required IconData icon}) {
  // final isDark = Theme.of(Get.c).brightness == Brightness.dark;
  return Container(
    padding: EdgeInsets.all(4.w),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 7.5.sp,
                    letterSpacing: 0.5)),
            Icon(icon, size: 14.sp, color: color.withOpacity(0.5)),
          ],
        ),
        SizedBox(height: 1.h),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.sp)),
      ],
    ),
  );
}
