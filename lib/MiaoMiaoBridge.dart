import 'dart:developer';
import 'dart:typed_data';

import 'utils.dart';
import 'package:flutter_blue/flutter_blue.dart';

import 'FreestyleLibre.dart';

enum TOMATO_STATE {
  REQUEST_DATA_SENT,
  RECEIVING_DATA
}

const TOMATO_HEADER_LENGTH = 18;

class TomatoBridgePacket {

}

// https://github.com/NightscoutFoundation/xDrip/blob/2020.12.18/app/src/main/java/com/eveningoutpost/dexdrip/Models/Tomato.java#L237
class TomatoBridge {
  // https://infocenter.nordicsemi.com/index.jsp?topic=%2Fcom.nordic.infocenter.sdk5.v15.3.0%2Fble_sdk_app_nus_eval.html
  static const String NRF_SERVICE = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String NRF_CHR_RX = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String NRF_CHR_TX = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

  BluetoothDevice _device;
  BluetoothService _service;
  BluetoothCharacteristic _rx;
  BluetoothCharacteristic _tx;

  Uint8List _rxBuf;

  TOMATO_STATE state;

  TomatoBridge._create(BluetoothDevice device){
    _device = device;
    _rxBuf = Uint8List(0);
  }

  void _onRX(List<int> data) {
    log("Recieved data: ${toHex(data)}", name: "TomatoBridge");
    if (state == TOMATO_STATE.REQUEST_DATA_SENT) {
      if (data.length == 1 && data[0] == 0x34) {
        log("No sensor found near bridge", name: "TomatoBridge");
        return;
      } else if (data.length == 1 && data[0] == 0x32) {
        // allow sensor confirm (2B), make it send data every 5 minutes (didn't work?) (2B), start reading (1B)
        bridgeRawWrite(Uint8List.fromList(
            [0xD3, 0x01, 0xD1, 0x05, 0xF0]
        ).buffer);
        // uh, we can't ensure async write to be sent, but IT SHOULD WORK ANYWAY!
        return;
      } else if (data.length >= TOMATO_HEADER_LENGTH && data[0] == 0x28) {
        var pkg_len = (data[1] << 8) + data[2];
        log("Got initial packet with size: $pkg_len", name: "TomatoBridge");
        // starting accumulating packet data in buffer
        _rxBuf = Uint8List.fromList(data);
        // no need to append, this is initial packet
        // TODO: check if there's any packet assembled
        state = TOMATO_STATE.RECEIVING_DATA;
      } else {
        log("Unknown initial packet from bridge", name: "TomatoBridge");
        return;
      }
    } else if (state == TOMATO_STATE.RECEIVING_DATA) {
      // MOAR DATAAAA!
      // TODO: check if there's any packet assembled
      // TODO: check for checksum and reset bridge on error
      _rxBuf = _rxBuf + Uint8List.fromList(data);
    } else {
      // only option is NULL-STATE - class not initialized
      log("RX on uninitialized bridge", name: "TomatoBridge");
      return;
    }
  }

  void _parsePacketsFromBuffer(){
    if(_rxBuf.length < FREESTYLELIBRE_PACKET_LENGTH + TOMATO_HEADER_LENGTH + 1) {
      //Log.e(TAG,"Getting out, since not enough data s_acumulatedSize = " + s_acumulatedSize);
      return;
    }

    var libre_data = _rxBuf.sublist(TOMATO_HEADER_LENGTH, TOMATO_HEADER_LENGTH + FREESTYLELIBRE_PACKET_LENGTH);

  }

  static Future<TomatoBridge> create(BluetoothDevice device) async {
    var self = TomatoBridge._create(device);

    if(!await isTomato(device)) throw Exception("WTF.");

    self._service = (await device.discoverServices()).firstWhere((srv) => srv.uuid.toString() == NRF_SERVICE);

    self._rx = self._service.characteristics.firstWhere((chr) => chr.uuid.toString() == NRF_CHR_RX);
    self._tx = self._service.characteristics.firstWhere((chr) => chr.uuid.toString() == NRF_CHR_TX);

    await self._rx.setNotifyValue(true);
    self._rx.value.listen(self._onRX);

    return self;
  }

  static Future<bool> isTomato(BluetoothDevice device) async {
    if(!(device.name.startsWith("miaomiao") || device.name.startsWith("watlaa"))){
      return false;
    }

    return (await device.discoverServices()).any((srv) => srv.uuid.toString() == NRF_SERVICE);
  }

  // @override
  // Future<ByteBuffer> bridgeRawRead() async {
  //   var buf = _rxBuf;
  //   _rxBuf = Uint8List(0);
  //
  //   return buf.buffer;
  // }

  @override
  Future<Null> bridgeRawWrite(ByteBuffer data) async {
    log("Sending data: ${toHex(Uint8List.view(data))}", name: "TomatoBridge");
    await _tx.write(data.asUint8List());
  }

  void initSensor() async {
    // Make tomato send data every 5 minutes (0xD1, 0x05), start reading (0xF0)
    // I'VE DUCKING NO IDEA WHAT IT REALLY MEANS AND FOUND NOTHING ABOUT IT, JUST NEED TO PRAY IT WORKS
    await bridgeRawWrite(Uint8List.fromList([0xD1, 0x05, 0xF0]).buffer);
    log("Sent init sequence", name: "TomatoBridge");
    state = TOMATO_STATE.REQUEST_DATA_SENT;
  }
}
