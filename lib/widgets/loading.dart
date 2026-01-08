import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class Loading extends StatelessWidget {
  final double size;

  const Loading({required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpinKitPouringHourGlass(
        color: Colors.black87,
        size: size,
      ),
    );
  }
}

class Loading2 extends StatelessWidget {
  final double size;

  const Loading2({required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpinKitCubeGrid(
        color: Colors.black87,
        size: size,
      ),
    );
  }
}

class Loading3 extends StatelessWidget {
  final double size;

  const Loading3({required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpinKitWaveSpinner(
        color: Colors.black87,
        size: size,
      ),
    );
  }
}