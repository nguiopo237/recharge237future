import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../style/middletext.dart';

class Boxwidget extends StatelessWidget {
  Color colorbox;
  Color colortext;
  String? title;
  String? subtitle;
  double? size;
  void Function()? ontape;

  Boxwidget(
      {super.key,
      this.ontape,
      this.colorbox = Colors.white,
      this.size = 22,
      this.colortext = Colors.black,
      this.title = "",
      this.subtitle = ""});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: ontape,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          decoration: BoxDecoration(
              color: colorbox, borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Middletext(
                  text: title.toString(),
                  color: colortext,
                  fontWeight: FontWeight.w600,
                  size: 14.sp,
                ),
                Middletext(
                  textAlign: TextAlign.center,
                  text: subtitle.toString(),
                  color: colortext,
                  fontWeight: FontWeight.bold,
                  size: size!.sp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
