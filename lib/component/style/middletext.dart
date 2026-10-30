
import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

class Middletext extends StatefulWidget {
  final String text;
  final String? private;
  Color? color;
  final TextAlign textAlign;
  final double size;
  final FontWeight fontWeight;
  final FontStyle? fontStyle;
  final TextOverflow? textoverflow;
  final int? maxLines;
  final double? height;
  final bool? softWrap;
  final TextDecoration underline;

  Middletext({super.key, 
    required this.text,
    this.underline = TextDecoration.none,
    this.height,
    this.private,
    this.softWrap = false,
    this.color = Colors.black,
    this.size = 12,
    this.fontWeight = FontWeight.w400,
    this.fontStyle,
    this.textAlign = TextAlign.start,
    this.textoverflow = TextOverflow.ellipsis,
    this.maxLines = 8,
  });

  @override
  State<Middletext> createState() => _MiddletextState();
}

class _MiddletextState extends State<Middletext> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    // AppConstants.addscreenshot();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.text,
      softWrap: widget.softWrap,
      textAlign: widget.textAlign,
      overflow: widget.textoverflow,
      maxLines: widget.maxLines,
      style: GoogleFonts.lato(
        textStyle: TextStyle(
          decoration: widget.underline,
        ),
        color: widget.color,
        fontSize: widget.size,
        fontWeight: widget.fontWeight,
        fontStyle: widget.fontStyle,
        height: widget.height,
      ),
    );
  }
}
