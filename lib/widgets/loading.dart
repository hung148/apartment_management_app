import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class Loading extends StatelessWidget {
  final double size;
  final Color? color;

  const Loading({super.key, required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpinKitPouringHourGlass(
        color: color ?? Colors.black87,
        size: size,
      ),
    );
  }
}

class Loading2 extends StatelessWidget {
  final double size;
  final Color? color;

  const Loading2({super.key, required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpinKitCubeGrid(
        color: color ?? Colors.black87,
        size: size,
      ),
    );
  }
}

class Loading3 extends StatelessWidget {
  final double size;
  final Color? color;

  const Loading3({super.key, required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpinKitWaveSpinner(
        color: color ?? Colors.black87,
        size: size,
      ),
    );
  }
}