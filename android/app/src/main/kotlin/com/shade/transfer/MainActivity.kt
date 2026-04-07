package com.shade.transfer

import android.app.PendingIntent
import android.content.Intent
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "shade_transfer/nfc"
    private var nfcAdapter: NfcAdapter? = null
    private var methodChannel: MethodChannel? = null
    private var isSessionActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> {
                    val available = nfcAdapter != null && nfcAdapter!!.isEnabled
                    result.success(available)
                }
                "startSession" -> {
                    if (nfcAdapter != null && nfcAdapter!!.isEnabled) {
                        isSessionActive = true
                        result.success(null)
                    } else {
                        result.error("NFC_UNAVAILABLE", "NFC is not available", null)
                    }
                }
                "writeTag" -> {
                    val data = call.argument<String>("data")
                    if (data != null && nfcAdapter != null && nfcAdapter!!.isEnabled) {
                        // For writing, we need to handle in onNewIntent or foreground dispatch
                        result.success(null)
                    } else {
                        result.error("NFC_UNAVAILABLE", "NFC is not available", null)
                    }
                }
                "stopSession" -> {
                    isSessionActive = false
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isSessionActive && NfcAdapter.ACTION_NDEF_DISCOVERED == intent.action ||
            NfcAdapter.ACTION_TAG_DISCOVERED == intent.action) {
            val tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
            tag?.let {
                val ndef = Ndef.get(it)
                ndef?.let { ndefTag ->
                    ndefTag.connect()
                    val ndefMessage = ndefTag.ndefMessage
                    ndefMessage?.let { message ->
                        for (record in message.records) {
                            if (record.tnf == NdefRecord.TNF_WELL_KNOWN &&
                                record.type.contentEquals(NdefRecord.RTD_TEXT)) {
                                val payload = String(record.payload, Charsets.UTF_8)
                                methodChannel?.invokeMethod("onTagDiscovered", payload)
                                break
                            }
                        }
                    }
                    ndefTag.close()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (isSessionActive) {
            val intent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            nfcAdapter?.enableForegroundDispatch(this, PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE), null, null)
        }
    }

    override fun onPause() {
        super.onPause()
        nfcAdapter?.disableForegroundDispatch(this)
    }
}
