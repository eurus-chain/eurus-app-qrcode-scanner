import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'qr_scanner_overlay_shape.dart';
import 'types/barcode.dart';
import 'types/barcode_format.dart';
import 'types/camera.dart';
import 'types/camera_exception.dart';
import 'types/features.dart';

typedef QRViewCreatedCallback = void Function(QRViewController);
typedef PermissionSetCallback = void Function(QRViewController, bool);

/// The [QRView] is the view where the camera
/// and the barcode scanner gets displayed.
class QRView extends StatefulWidget {
  const QRView({
    @required Key key,
    @required this.onQRViewCreated,
    @required this.pgTitle,
    this.overlay,
    this.overlayMargin = EdgeInsets.zero,
    this.cameraFacing = CameraFacing.back,
    this.onPermissionSet,
    this.formatsAllowed,
  })  : assert(key != null),
        assert(onQRViewCreated != null),
        super(key: key);

  /// [onQRViewCreated] gets called when the view is created
  final QRViewCreatedCallback onQRViewCreated;

  /// Use [overlay] to provide an overlay for the view.
  /// This can be used to create a certain scan area.
  final QrScannerOverlayShape overlay;

  /// Use [overlayMargin] to provide a margin to [overlay]
  final EdgeInsetsGeometry overlayMargin;

  /// Set which camera to use on startup.
  ///
  /// [cameraFacing] can either be CameraFacing.front or CameraFacing.back.
  /// Defaults to CameraFacing.back
  final CameraFacing cameraFacing;

  /// Calls the provided [onPermissionSet] callback when the permission is set.
  final PermissionSetCallback onPermissionSet;

  /// Use [formatsAllowed] to specify which formats needs to be scanned.
  final List<BarcodeFormat> formatsAllowed;

  /// Scanner Page App Bar Title
  final String pgTitle;

  @override
  State<StatefulWidget> createState() => _QRViewState();
}

class _QRViewState extends State<QRView> with SingleTickerProviderStateMixin {
  var _channel;
  AnimationController _aniCon;
  bool lightOn = false;

  @override
  void initState() {
    _aniCon = AnimationController(vsync: this, duration: Duration(seconds: 3))
      ..repeat();
    super.initState();
  }

  @override
  void dispose() {
    _aniCon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener(
      onNotification: onNotification,
      child: SizeChangedLayoutNotifier(
        child: (widget.overlay != null)
            ? _getPlatformQrViewWithOverlay()
            : _getPlatformQrView(),
      ),
    );
  }

  bool onNotification(notification) {
    Future.microtask(
      () => {
        QRViewController.updateDimensions(
          widget.key,
          _channel,
          scanArea: widget.overlay != null ? (widget.overlay).cutOutSize : 0.0,
        )
      },
    );
    return false;
  }

  Widget _getPlatformQrViewWithOverlay() {
    return Stack(
      children: [
        _loadingScreen(),
        _getPlatformQrView(),
        Container(
          padding: widget.overlayMargin,
          decoration: ShapeDecoration(
            shape: widget.overlay,
          ),
        ),
        _getScanAnimation(),
      ],
    );
  }

  Widget _loadingScreen() {
    return Container(
      alignment: Alignment(0, 0),
      color: Colors.black,
      child: Icon(
        Icons.qr_code_rounded,
        color: Colors.white,
        size: widget.overlay.cutOutSize * 0.7,
      ),
    );
  }

  Widget _getPlatformQrView() {
    Widget _platformQrView;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        _platformQrView = AndroidView(
          viewType: 'net.touchcapture.qr.flutterqr/qrview',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams:
              _QrCameraSettings(cameraFacing: widget.cameraFacing).toMap(),
          creationParamsCodec: StandardMessageCodec(),
        );
        break;
      case TargetPlatform.iOS:
        _platformQrView = UiKitView(
          viewType: 'net.touchcapture.qr.flutterqr/qrview',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams:
              _QrCameraSettings(cameraFacing: widget.cameraFacing).toMap(),
          creationParamsCodec: StandardMessageCodec(),
        );
        break;
      default:
        throw UnsupportedError(
            "Trying to use the default webview implementation for $defaultTargetPlatform but there isn't a default one");
    }
    return _platformQrView;
  }

  Widget _getScanAnimation() {
    return Center(
      child: Container(
        width: widget.overlay.cutOutSize,
        height: widget.overlay.cutOutSize,
        alignment: Alignment(0, -1),
        child: AnimatedBuilder(
          animation: _aniCon.view,
          builder: (_, __) {
            var scanAniRatio = 0.25;
            var scanAniSize = widget.overlay.cutOutSize * scanAniRatio;
            var yOffset =
                ((_aniCon.value - scanAniRatio) / (1 - scanAniRatio)) *
                    widget.overlay.cutOutSize;

            return Transform.translate(
              offset: Offset(0, _aniCon.value < scanAniRatio ? 0 : yOffset),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.overlay.borderColor.withOpacity(
                          _aniCon.value >= scanAniRatio
                              ? 0
                              : (1 - (_aniCon.value * 4))),
                      widget.overlay.borderColor
                    ],
                  ),
                ),
                height: _aniCon.value < scanAniRatio
                    ? (_aniCon.value * widget.overlay.cutOutSize)
                    : _aniCon.value > (1 - scanAniRatio) &&
                            (widget.overlay.cutOutSize - yOffset) < scanAniSize
                        ? widget.overlay.cutOutSize - yOffset
                        : scanAniSize,
                width: widget.overlay.cutOutSize,
                child: Padding(
                  padding: EdgeInsets.zero,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    // We pass the cutout size so that the scanner respects the scan area.
    var cutOutSize = 0.0;
    if (widget.overlay != null) {
      cutOutSize = (widget.overlay).cutOutSize;
    }

    _channel = MethodChannel('net.touchcapture.qr.flutterqr/qrview_$id');

    // Start scan after creation of the view
    final controller = QRViewController._(
        _channel, widget.key, cutOutSize, widget.onPermissionSet)
      .._startScan(widget.key, cutOutSize, widget.formatsAllowed);

    // Initialize the controller for controlling the QRView
    if (widget.onQRViewCreated != null) {
      widget.onQRViewCreated(controller);
    }
  }
}

class _QrCameraSettings {
  _QrCameraSettings({
    this.cameraFacing,
  });

  final CameraFacing cameraFacing;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'cameraFacing': cameraFacing.index,
    };
  }
}

class QRViewController {
  QRViewController._(MethodChannel channel, GlobalKey qrKey, double scanArea,
      PermissionSetCallback onPermissionSet)
      : _channel = channel {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onRecognizeQR':
          if (call.arguments != null) {
            final args = call.arguments as Map;
            final code = args['code'] as String;
            final rawType = args['type'] as String;
            // Raw bytes are only supported by Android.
            final rawBytes = args['rawBytes'] as List<int>;
            final format = BarcodeTypesExtension.fromString(rawType);
            if (format != null) {
              final barcode = Barcode(code, format, rawBytes);
              _scanUpdateController.sink.add(barcode);
            } else {
              throw Exception('Unexpected barcode type $rawType');
            }
          }
          break;
        case 'onPermissionSet':
          await getSystemFeatures(); // if we have no permission all features will not be avaible
          if (call.arguments != null) {
            if (call.arguments as bool) {
              _hasPermissions = true;
            } else {
              _hasPermissions = false;
            }
            if (onPermissionSet != null) {
              onPermissionSet(this, call.arguments as bool);
            }
          }
          break;
      }
    });
  }

  final MethodChannel _channel;
  final StreamController<Barcode> _scanUpdateController =
      StreamController<Barcode>();

  Stream<Barcode> get scannedDataStream => _scanUpdateController.stream;

  SystemFeatures _features;
  bool _hasPermissions;

  SystemFeatures get systemFeatures => _features;
  bool get hasPermissions => _hasPermissions;

  /// Starts the barcode scanner
  Future<void> _startScan(GlobalKey key, double cutOutSize,
      List<BarcodeFormat> barcodeFormats) async {
    // We need to update the dimension before the scan is started.
    QRViewController.updateDimensions(key, _channel, scanArea: cutOutSize);
    return _channel.invokeMethod(
        'startScan', barcodeFormats?.map((e) => e.asInt())?.toList() ?? []);
  }

  /// Gets information about which camera is active.
  Future<CameraFacing> getCameraInfo() async {
    try {
      return CameraFacing
          .values[await _channel.invokeMethod('getCameraInfo') as int];
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Flips the camera between available modes
  Future<CameraFacing> flipCamera() async {
    try {
      return CameraFacing
          .values[await _channel.invokeMethod('flipCamera') as int];
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Get flashlight status
  Future<bool> getFlashStatus() async {
    try {
      return await _channel.invokeMethod('getFlashInfo');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Toggles the flashlight between available modes
  Future<void> toggleFlash() async {
    try {
      await _channel.invokeMethod('toggleFlash') as bool;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Pauses barcode scanning
  Future<void> pauseCamera() async {
    try {
      await _channel.invokeMethod('pauseCamera');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Resumes barcode scanning
  Future<void> resumeCamera() async {
    try {
      await _channel.invokeMethod('resumeCamera');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Returns which features are available on device.
  Future<SystemFeatures> getSystemFeatures() async {
    try {
      var features =
          await _channel.invokeMapMethod<String, dynamic>('getSystemFeatures');
      return SystemFeatures.fromJson(features);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Disposes the barcode stream.
  void dispose() {
    _scanUpdateController.close();
  }

  /// Updates the view dimensions for iOS.
  static void updateDimensions(GlobalKey key, MethodChannel channel,
      {double scanArea}) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final RenderBox renderBox = key.currentContext.findRenderObject();
      channel.invokeMethod('setDimensions', {
        'width': renderBox.size.width,
        'height': renderBox.size.height,
        'scanArea': scanArea ?? 0
      });
    }
  }
}
