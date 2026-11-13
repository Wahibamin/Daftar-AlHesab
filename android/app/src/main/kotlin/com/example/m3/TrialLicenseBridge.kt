package com.example.m3

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.UUID
import java.util.TimeZone
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Install-bound storage only. Never opens the accounting database. */
class TrialLicenseStore(private val context: Context, private val name: String = "daftar_license") {
    private val directory = File(context.noBackupFilesDir, name)
    private val marker get() = AtomicFile(File(directory, "installation"))
    private val state get() = AtomicFile(File(directory, "state.bin"))
    private val alias = "${context.packageName}.$name.aes.v1"
    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun read(): Map<String, Any> {
        val keys = keyStore()
        val identityExists = marker.baseFile.exists()
        val keyExists = keys.containsAlias(alias)
        // Restored ciphertext without this installation's identity/key is NOT a license.
        if (!identityExists && !keyExists) return mapOf("status" to "empty")
        if (!identityExists || !keyExists || !state.baseFile.exists()) return mapOf("status" to "invalid")
        return try {
            val identity = marker.readFully().toString(Charsets.UTF_8)
            val bytes = state.readFully()
            require(bytes.size > 28)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, keys.getKey(alias, null), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            cipher.updateAAD((context.packageName + ":" + identity).toByteArray(Charsets.UTF_8))
            val envelope = JSONObject(cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8))
            require(envelope.getString("installation") == identity)
            mapOf("status" to "ok", "payload" to envelope.getString("payload"))
        } catch (_: Exception) { mapOf("status" to "invalid") }
    }

    fun write(payload: String) {
        require(payload.toByteArray(Charsets.UTF_8).size <= 16384)
        JSONObject(payload) // reject malformed payload without logging it
        directory.mkdirs()
        val keys = keyStore()
        if (!marker.baseFile.exists() && !keys.containsAlias(alias)) {
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
            generator.generateKey()
            atomicWrite(marker, UUID.randomUUID().toString().toByteArray(Charsets.UTF_8))
        }
        require(marker.baseFile.exists() && keys.containsAlias(alias))
        val identity = marker.readFully().toString(Charsets.UTF_8)
        val envelope = JSONObject().put("installation", identity).put("payload", payload).toString()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keys.getKey(alias, null) as SecretKey)
        cipher.updateAAD((context.packageName + ":" + identity).toByteArray(Charsets.UTF_8))
        atomicWrite(state, cipher.iv + cipher.doFinal(envelope.toByteArray(Charsets.UTF_8)))
    }

    private fun atomicWrite(file: AtomicFile, bytes: ByteArray) {
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) }
        catch (e: Exception) { file.failWrite(stream); throw e }
    }
}

class TrialLicenseBridge(context: Context, channel: MethodChannel) {
    init {
        val store = TrialLicenseStore(context.applicationContext)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> result.success(store.read())
                    "write" -> { store.write(call.arguments as String); result.success(null) }
                    "clock" -> result.success(mapOf("utcMs" to System.currentTimeMillis(),
                        "elapsedMs" to SystemClock.elapsedRealtime(),
                        "offsetMinutes" to TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 60000,
                        "bootId" to Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1).toString()))
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("LICENSE_STORAGE", "Local license verification unavailable", null) }
        }
    }
}
