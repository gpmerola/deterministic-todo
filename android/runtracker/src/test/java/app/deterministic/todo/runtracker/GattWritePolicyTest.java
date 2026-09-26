package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import android.bluetooth.BluetoothGattCharacteristic;

import org.junit.Test;

public final class GattWritePolicyTest {
    @Test public void huamiAuthPrefersAdvertisedNoResponseWrites() {
        int both = BluetoothGattCharacteristic.PROPERTY_WRITE
            | BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE;
        assertEquals(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
            GattWritePolicy.select(both,
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT, true));
    }

    @Test public void regularControlKeepsAcknowledgedWriteWhenAvailable() {
        int both = BluetoothGattCharacteristic.PROPERTY_WRITE
            | BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE;
        assertEquals(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
            GattWritePolicy.select(both,
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE, false));
    }

    @Test public void fallsBackToOnlyAdvertisedWriteType() {
        assertEquals(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
            GattWritePolicy.select(
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT, false));
    }
}
