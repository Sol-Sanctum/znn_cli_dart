import 'package:dcli/dcli.dart' hide verbose;
import 'package:znn_sdk_dart/znn_sdk_dart.dart';
import 'src.dart';

void liquidityMenu() {
  print('  ${white('Liquidity')}');
}

void liquidityAdminMenu() {
  print('  ${white('Liquidity Admin')}');
}

Future<void> liqidityFunctions() async {
  switch (args[0].split('.')[1]) {
    default:
      invalidCommand();
  }
}
