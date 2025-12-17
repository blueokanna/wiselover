import '../frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

String live2DCoreLoader() =>
    RustLib.instance.api.crateApiWiseLoverBootApiLive2DCoreLoader();

String live2DCoreVersion() =>
    RustLib.instance.api.crateApiWiseLoverBootApiLive2DCoreVersion();

String live2DCoreLatestMocVersion() =>
    RustLib.instance.api.crateApiWiseLoverBootApiLive2DCoreLatestMocVersion();

bool live2DCoreCheckMocConsistency({required List<int> mocBytes}) => RustLib
    .instance
    .api
    .crateApiWiseLoverBootApiLive2DCoreCheckMocConsistency(mocBytes: mocBytes);

String live2DCoreMocVersion({required List<int> mocBytes}) => RustLib
    .instance
    .api
    .crateApiWiseLoverBootApiLive2DCoreMocVersion(mocBytes: mocBytes);
