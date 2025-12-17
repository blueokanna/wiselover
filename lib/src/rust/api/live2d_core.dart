import '../frb_generated.dart';
import 'wise_lover_boot_api.dart';

String live2dCoreLoader() => live2DCoreLoader();

Future<void> wiseLoverBootInitApp() =>
    RustLib.instance.api.crateApiWiseLoverBootApiWiseLoverBootInitApp();
