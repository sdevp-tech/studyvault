// MainActivity.kt
package com.example.study_vault

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.study_vault/litert"
    private val EVENT_CHANNEL = "com.example.study_vault/litert_stream"
    private lateinit var plugin: LiteRtPlugin

    // نطاق كوروتين واحد مملوك للـ Activity بدلاً من إنشاء نطاق جديد غير قابل
    // للإلغاء عند كل استدعاء (كان ذلك يسرّب الموارد الأصلية عند إعادة إنشاء الـ Activity).
    private val mainScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        plugin = LiteRtPlugin(context)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        val path = call.argument<String>("modelPath") ?: ""
                        val backend = call.argument<String>("backend") ?: "cpu"
                        val systemPrompt = call.argument<String>("systemPrompt") ?: ""
                        val maxTokens = call.argument<Int>("maxTokens") ?: 256
                        val temperature = call.argument<Double>("temperature") ?: 0.6
                        val topK = call.argument<Int>("topK") ?: 30
                        val supportVision = call.argument<Boolean>("supportVision") ?: false // ✅ استلام المتغير

                        if (path.isEmpty()) {
                            result.error("INVALID_PATH", "Model path is empty", null)
                        } else {
                            mainScope.launch {
                                try {
                                    plugin.initializeEngine(
                                        modelPath = path,
                                        backend = backend,
                                        systemPrompt = systemPrompt,
                                        maxTokens = maxTokens,
                                        temperature = temperature.toFloat(),
                                        topK = topK,
                                        supportVision = supportVision // ✅ تمريره للـ Plugin
                                    )
                                    withContext(Dispatchers.Main) { result.success(true) }
                                } catch (e: Exception) {
                                    withContext(Dispatchers.Main) {
                                        result.error("INIT_ERROR", "Failed to load model: ${e.message}", null)
                                    }
                                }
                            }
                        }
                    }
                    "stop" -> {
                        plugin.stopGeneration()
                        result.success(null)
                    }
                    "close" -> {
                        mainScope.launch {
                            try {
                                plugin.close()
                                withContext(Dispatchers.Main) { result.success(null) }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) { result.error("CLOSE_ERR", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events != null) {
                        val args = arguments as? Map<*, *>
                        val prompt = args?.get("prompt") as? String ?: ""
                        val imagePath = args?.get("imagePath") as? String

                        mainScope.launch {
                            plugin.startGeneration(prompt, imagePath, events)
                        }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    plugin.stopGeneration()
                }
            })
    }

    override fun onDestroy() {
        // نطلق الإغلاق على النطاق المملوك لضمان إتمام تنظيف الموارد الأصلية،
        // بدلاً من إنشاء نطاق منفصل قد يُقتل قبل اكتمال الإغلاق.
        mainScope.launch {
            try {
                plugin.close()
            } catch (e: Exception) {
                // تجاهل أخطاء الإغلاق النهائي
            }
        }
        super.onDestroy()
    }
}
