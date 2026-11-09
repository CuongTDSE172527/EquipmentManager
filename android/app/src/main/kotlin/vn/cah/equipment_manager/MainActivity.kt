package vn.cah.equipment_manager

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val updateExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.cah.equipment_manager/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                    "openPermission" -> try {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        result.success(null)
                    } catch (ex: Exception) {
                        result.error("INSTALL_PERMISSION", "Không mở được quyền cài ứng dụng. Vào Cài đặt Android để cho phép nguồn EquipmentManager.", null)
                    }
                    "verify", "install" -> {
                        val path = call.argument<String>("path")
                        val version = call.argument<String>("version")
                        val code = call.argument<Number>("code")?.toLong()
                        val digest = call.argument<String>("sha256")
                        updateExecutor.execute {
                            try {
                                val file = verifyUpdate(path, version, code, digest)
                                runOnUiThread {
                                    try {
                                        check(!isFinishing && !isDestroyed) { "Màn hình đã đóng. Hãy mở lại phần cập nhật." }
                                        if (call.method == "install") {
                                            check(packageManager.canRequestPackageInstalls()) { "Hãy cho phép EquipmentManager cài ứng dụng từ nguồn này trước." }
                                            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                                            val intent = Intent(Intent.ACTION_VIEW)
                                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                            startActivity(intent)
                                        }
                                        result.success(null)
                                    } catch (ex: Exception) { result.error("INSTALL_FAILED", ex.message, null) }
                                }
                            } catch (ex: Exception) {
                                runOnUiThread { result.error("INVALID_UPDATE", ex.message ?: "Không xác minh được APK.", null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun verifyUpdate(path: String?, version: String?, code: Long?, digest: String?): File {
        require(path != null && version != null && code != null && digest != null) { "Thiếu thông tin bộ cài." }
        val root = File(filesDir, "updates").canonicalFile
        val file = File(path).canonicalFile
        require(file.isFile && file.path.startsWith(root.path + File.separator) && file.extension == "apk") { "APK nằm ngoài thư mục cập nhật." }
        val sha = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val count = input.read(buffer); if (count < 0) break; sha.update(buffer, 0, count) }
        }
        val actual = sha.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
        require(actual == digest) { "SHA-256 của APK đã thay đổi. Hãy tải lại." }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val installed = packageManager.getPackageInfo(packageName, flags)
        val archive = packageManager.getPackageArchiveInfo(file.path, flags)
            ?: throw IllegalArgumentException("Không đọc được APK tải về.")
        val installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        val archiveCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        require(archive.packageName == packageName && archive.versionName == version && archiveCode == code && archiveCode > installedCode) {
            "APK không đúng EquipmentManager hoặc không phải phiên bản mới hơn."
        }
        require(signers(installed) == signers(archive) && signers(installed).isNotEmpty()) {
            "APK không cùng khóa ký với ứng dụng đang cài. Đã chặn cập nhật."
        }
        return file
    }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        }?.toSet() ?: emptySet()
    }

    override fun onDestroy() {
        updateExecutor.shutdown()
        super.onDestroy()
    }
}
