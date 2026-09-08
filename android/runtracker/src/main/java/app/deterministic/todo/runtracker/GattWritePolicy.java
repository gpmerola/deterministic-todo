package app.deterministic.todo.runtracker;

import android.bluetooth.BluetoothGattCharacteristic;

/** Selects a write type from the properties actually advertised by a characteristic. */
final class GattWritePolicy {
    private GattWritePolicy() {}

    static int select(int properties, int nativeWriteType, boolean preferNoResponse) {
        if (preferNoResponse
            && (properties & BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0) {
            return BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        }
        if ((properties & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0) {
            return BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT;
        }
        if ((properties & BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0) {
            return BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        }
        return nativeWriteType;
    }
}
