package com.example.m3

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import java.io.File
import java.security.KeyStore

/** Real Keystore QA in separate named stores. Never accesses accounting SQLite. */
class LicenseStorageInstrumentation : Instrumentation() {
    private var expectEmptyInstallation = false
    private var verifyDatabase = false
    override fun onCreate(arguments: Bundle?) {
        expectEmptyInstallation = arguments?.getString("expectEmpty") == "true"
        verifyDatabase = arguments?.getString("verifyDatabase") == "true"
        super.onCreate(arguments)
        start()
    }
    override fun onStart() {
        val context = targetContext
        val names = listOf("daftar_license_qa_a", "daftar_license_qa_b")
        val passed = mutableListOf<String>()
        var resultCode = Activity.RESULT_OK
        val result = Bundle()
        try {
            check(context.packageName == "com.example.m3" || context.packageName == "com.example.m3.licenseqa")
            fun checkCase(name: String, condition: Boolean) { check(condition) { name }; passed.add(name) }
            if (verifyDatabase) {
                check(context.packageName == "com.example.m3.licenseqa")
                android.database.sqlite.SQLiteDatabase.openDatabase(context.getDatabasePath("raf_erp.db").absolutePath, null,
                    android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { db ->
                    db.rawQuery("PRAGMA integrity_check", null).use { c ->
                        checkCase("native_sqlite_reopened_integrity_ok", c.moveToFirst() && c.getString(0) == "ok")
                    }
                    db.rawQuery("PRAGMA foreign_key_check", null).use { c ->
                        checkCase("native_sqlite_no_foreign_key_violations", c.count == 0)
                    }
                    db.rawQuery("SELECT (SELECT COUNT(*) FROM items), (SELECT COUNT(*) FROM invoices), (SELECT stock_quantity_int FROM items WHERE code='QA-BULK-0000')", null).use { c ->
                        checkCase("native_sqlite_fixture_survives_process_restart", c.moveToFirst() && c.getInt(0) == 503 && c.getInt(1) == 125 && c.getInt(2) == 380)
                    }
                    db.rawQuery("SELECT COUNT(*) FROM qa_atomic_probe", null).use { c ->
                        checkCase("forced_stop_mid_transaction_rolled_back", c.moveToFirst() && c.getInt(0) == 0)
                    }
                }
            }
            if (expectEmptyInstallation) {
                check(context.packageName == "com.example.m3.licenseqa")
                checkCase("reinstalled_default_license_store_empty", TrialLicenseStore(context).read()["status"] == "empty")
            }
            val a = TrialLicenseStore(context, names[0])
            val b = TrialLicenseStore(context, names[1])
            checkCase("fresh_native_store_empty", a.read()["status"] == "empty")
            val payload = "{\"qa\":true,\"no_accounting_data\":true}"
            a.write(payload)
            checkCase("keystore_encrypt_decrypt", a.read()["payload"] == payload)
            checkCase("new_store_instance_preserves_state", TrialLicenseStore(context, names[0]).read()["payload"] == payload)
            val original = File(context.noBackupFilesDir, "${names[0]}/state.bin").readBytes()
            checkCase("ciphertext_not_plaintext", !original.toString(Charsets.UTF_8).contains(payload))
            val target = File(context.noBackupFilesDir, "${names[1]}/state.bin")
            target.parentFile!!.mkdirs(); target.writeBytes(original)
            checkCase("restored_ciphertext_without_identity_not_active", b.read()["status"] == "empty")
            b.write(payload); target.writeBytes(original)
            checkCase("copied_ciphertext_wrong_key_rejected", b.read()["status"] == "invalid")
            original[original.lastIndex] = (original.last().toInt() xor 1).toByte()
            File(context.noBackupFilesDir, "${names[0]}/state.bin").writeBytes(original)
            checkCase("gcm_tamper_rejected", a.read()["status"] == "invalid")
            val lostKeys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            lostKeys.deleteEntry("${context.packageName}.${names[0]}.aes.v1")
            checkCase("lost_keystore_key_rejected", a.read()["status"] == "invalid")
            checkCase("lost_key_cannot_silently_restart_license", runCatching { a.write(payload) }.isFailure)
            File(context.noBackupFilesDir, "${names[1]}/installation").delete()
            checkCase("lost_installation_marker_rejected", b.read()["status"] == "invalid")
            result.putString("license_qa", passed.joinToString(",")); result.putInt("passed", passed.size)
        } catch (e: Exception) {
            resultCode = Activity.RESULT_CANCELED
            result.putString("license_qa_failure", e.javaClass.simpleName); result.putString("passed_before_failure", passed.joinToString(","))
        } finally {
            val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            for (name in names) {
                val folder = File(context.noBackupFilesDir, name)
                check(folder.canonicalFile.parentFile == context.noBackupFilesDir.canonicalFile)
                folder.listFiles()?.forEach { check(it.isFile); it.delete() }; folder.delete()
                val alias = "${context.packageName}.$name.aes.v1"
                if (keys.containsAlias(alias)) keys.deleteEntry(alias)
            }
            result.putBoolean("qa_files_cleaned", true)
        }
        finish(resultCode, result)
    }
}
