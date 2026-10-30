import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MiddleText extends StatelessWidget {
  final String text;
  final Color? color;
  final TextAlign textAlign;
  final double size;
  final double height;
  final FontWeight fontWeight;
  final FontStyle? fontStyle;
  final TextOverflow? textoverflow;
  final int? maxLines;
  final TextDecoration? decoration;

  const MiddleText({
    super.key,
    this.height = 1.6,
    required this.text,
    this.color,
    this.size = 18,
    this.fontWeight = FontWeight.w300,
    this.fontStyle,
    this.textAlign = TextAlign.center,
    this.textoverflow = TextOverflow.ellipsis,
    this.maxLines = 2,
    this.decoration = TextDecoration.none,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      overflow: textoverflow,
      maxLines: maxLines,
      style: GoogleFonts.ibmPlexSans(
        color: color,
        height: height,
        decoration: decoration,
        fontSize: size,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
      ),
    );
  }
}
